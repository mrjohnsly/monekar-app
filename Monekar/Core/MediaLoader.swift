import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

nonisolated enum MediaURL {
    static func resolve(
        _ reference: String, baseURL: URL, size: MonekarAPI.ThumbnailSize? = nil
    ) throws -> URL {
        let root = baseURL.appendingPathComponent("")
        guard !reference.isEmpty,
              let url = URL(string: reference, relativeTo: root)?.absoluteURL,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: true),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.scheme?.lowercased() == base.scheme?.lowercased(),
              components.host?.lowercased() == base.host?.lowercased(),
              port(components) == port(base),
              components.user == nil, components.password == nil, components.fragment == nil else {
            throw ConnectionFailure.invalidURL
        }
        if let size {
            var query = components.queryItems ?? []
            query.removeAll { $0.name == "size" }
            query.append(URLQueryItem(name: "size", value: String(size.rawValue)))
            components.queryItems = query
        }
        guard let resolved = components.url else { throw ConnectionFailure.invalidURL }
        return resolved
    }

    private static func port(_ components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
    }
}

nonisolated struct MediaResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
}

nonisolated struct MediaResource: Sendable {
    let data: Data
    let isPlaceholder: Bool

    init(data: Data, mimeType: String?) throws {
        let type = mimeType?.lowercased() ?? "application/octet-stream"
        guard !data.isEmpty, type.hasPrefix("image/") || type == "application/octet-stream" else {
            throw ConnectionFailure.invalidResponse
        }
        isPlaceholder = type == "image/svg+xml"
        if isPlaceholder {
            guard data.count <= 262_144 else { throw ConnectionFailure.invalidResponse }
            let parser = XMLParser(data: data)
            let validator = SVGValidator()
            parser.delegate = validator
            parser.shouldResolveExternalEntities = false
            guard parser.parse(), validator.isSVG else { throw ConnectionFailure.invalidResponse }
        }
        self.data = data
    }
}

private nonisolated final class SVGValidator: NSObject, XMLParserDelegate {
    var isSVG = false
    private var foundRoot = false

    func parser(
        _ parser: XMLParser, didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]
    ) {
        if !foundRoot {
            isSVG = elementName == "svg"
            foundRoot = true
        }
    }
}

@MainActor
final class MediaLoader {
    private struct Entry {
        let resource: MediaResource
        let etag: String?
        let expires: Date
        var accessed: UInt64
    }

    private struct Pending {
        let task: Task<MediaResource, any Error>
        var waiters: Set<UUID>
    }

    private let api: any APIService
    private let byteLimit: Int
    private let now: () -> Date
    private var sessionID: UUID?
    private var cache: [URL: Entry] = [:]
    private var pending: [URL: Pending] = [:]
    private var clock: UInt64 = 0
    var connectionID: UUID? { api.mediaSessionID }

    init(api: any APIService, byteLimit: Int = 32 * 1024 * 1024, now: @escaping () -> Date = Date.init) {
        self.api = api
        self.byteLimit = byteLimit
        self.now = now
        sessionID = api.mediaSessionID
    }

    func load(
        reference: String, size: MonekarAPI.ThumbnailSize? = nil, reload: Bool = false
    ) async throws -> MediaResource {
        try Task.checkCancellation()
        if sessionID != api.mediaSessionID {
            pending.values.forEach { $0.task.cancel() }
            pending.removeAll()
            cache.removeAll()
            sessionID = api.mediaSessionID
        }
        guard let baseURL = api.baseURL else { throw ConnectionFailure.invalidURL }
        let url = try MediaURL.resolve(reference, baseURL: baseURL, size: size)
        if reload { cache.removeValue(forKey: url) }
        clock &+= 1
        if var entry = cache[url], entry.expires > now() {
            entry.accessed = clock
            cache[url] = entry
            return entry.resource
        }
        let waiter = UUID()
        if pending[url] != nil {
            pending[url]?.waiters.insert(waiter)
        } else {
            let currentSession = sessionID
            let task = Task {
                let cached = self.cache[url]
                let result = try await self.api.mediaResponse(reference: url.absoluteString, etag: cached?.etag)
                try Task.checkCancellation()
                guard currentSession == self.api.mediaSessionID else { throw CancellationError() }
                return try self.store(result, cached: cached, url: url)
            }
            pending[url] = Pending(task: task, waiters: [waiter])
        }
        let task = pending[url]!.task
        defer { release(url, waiter: waiter) }
        return try await withTaskCancellationHandler {
            let resource = try await task.value
            try Task.checkCancellation()
            return resource
        } onCancel: {
            Task { @MainActor in self.release(url, waiter: waiter) }
        }
    }

    private func release(_ url: URL, waiter: UUID) {
        guard pending[url]?.waiters.remove(waiter) != nil else { return }
        if pending[url]?.waiters.isEmpty == true {
            pending.removeValue(forKey: url)?.task.cancel()
        }
    }

    private func store(_ result: MediaResponse, cached: Entry?, url: URL) throws -> MediaResource {
        let response = result.response
        let resource: MediaResource
        if response.statusCode == 304 {
            guard let cached else { throw ConnectionFailure.invalidResponse }
            resource = cached.resource
        } else {
            guard response.statusCode == 200 else { throw ConnectionFailure.invalidResponse }
            resource = try MediaResource(data: result.data, mimeType: response.mimeType)
        }
        let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "")
            .lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        cache.removeValue(forKey: url)
        guard !directives.contains("no-store"), resource.data.count <= byteLimit else { return resource }
        let maxAge = directives.first { $0.hasPrefix("max-age=") }
            .flatMap { TimeInterval($0.dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\""))) } ?? 0
        let age = TimeInterval(response.value(forHTTPHeaderField: "Age") ?? "") ?? 0
        let freshness = directives.contains("no-cache") ? 0 : max(0, maxAge - age)
        while cache.values.reduce(0, { $0 + $1.resource.data.count }) + resource.data.count > byteLimit {
            guard let oldest = cache.min(by: { $0.value.accessed < $1.value.accessed })?.key else { break }
            cache.removeValue(forKey: oldest)
        }
        cache[url] = Entry(
            resource: resource,
            etag: response.value(forHTTPHeaderField: "ETag") ?? (response.statusCode == 304 ? cached?.etag : nil),
            expires: now().addingTimeInterval(freshness), accessed: clock
        )
        return resource
    }
}
