import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct MediaLoaderTests {
    private let base = URL(string: "https://server.local/proxy")!

    @Test func resolvesRootAndInstallationRelativeURLs() throws {
        #expect(try MediaURL.resolve("/api/v1/images/1/original", baseURL: base).absoluteString
            == "https://server.local/api/v1/images/1/original")
        #expect(try MediaURL.resolve("api/v1/images/1/original", baseURL: base).absoluteString
            == "https://server.local/proxy/api/v1/images/1/original")
        #expect(try MediaURL.resolve("https://SERVER.local:443/a%20b", baseURL: base).path == "/a b")
    }

    @Test(arguments: MonekarAPI.ThumbnailSize.allCases)
    func resolvesEveryThumbnailSize(_ size: MonekarAPI.ThumbnailSize) throws {
        let url = try MediaURL.resolve("/thumbnail?size=256&other=1", baseURL: base, size: size)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [
            URLQueryItem(name: "other", value: "1"),
            URLQueryItem(name: "size", value: String(size.rawValue)),
        ])
    }

    @Test(arguments: [
        "", "//other.local/image", "https://other.local/image", "http://server.local/image",
        "https://server.local:444/image", "file:///image", "/image#fragment",
        "https://" + "alice" + ":" + "secret" + "@server.local/image",
    ])
    func rejectsUnsafeMediaURLs(_ reference: String) {
        #expect(throws: ConnectionFailure.invalidURL) { try MediaURL.resolve(reference, baseURL: base) }
    }

    @Test(arguments: ["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "image/avif", "image/tiff", "application/octet-stream"])
    func acceptsServerRasterMediaTypes(_ type: String) throws {
        let resource = try MediaResource(data: Data([1]), mimeType: type)
        #expect(!resource.isPlaceholder)
    }

    @Test func handlesSVGPlaceholdersAndRejectsInvalidResponses() throws {
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg"><rect width="128" height="128"/></svg>"#.utf8)
        #expect(try MediaResource(data: svg, mimeType: "image/svg+xml").isPlaceholder)
        #expect(throws: ConnectionFailure.invalidResponse) {
            try MediaResource(data: Data("<html/>".utf8), mimeType: "image/svg+xml")
        }
        #expect(throws: ConnectionFailure.invalidResponse) {
            try MediaResource(data: Data([1]), mimeType: "text/html")
        }
        #expect(throws: ConnectionFailure.invalidResponse) {
            try MediaResource(data: Data(), mimeType: "image/jpeg")
        }
    }

    @Test func authenticatesThumbnailsAndOriginalsAndRevalidatesETags() async throws {
        let transport = MediaTransport()
        transport.headers = ["Content-Type": "image/webp", "ETag": "\"version-1\""]
        let api = try makeAPI(transport)
        let loader = MediaLoader(api: api)
        let first = try await loader.load(reference: "/api/v1/images/1/thumbnail", size: .large)
        transport.status = 304
        transport.body = Data()
        let second = try await loader.load(reference: "/api/v1/images/1/thumbnail", size: .large)
        #expect(first.data == second.data)
        #expect(transport.requests.count == 2)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"version-1\"")
        #expect(transport.requests.last?.url?.query == "size=512")
        transport.status = 200
        transport.body = Data([2])
        _ = try await loader.load(reference: "/api/v1/images/1/original")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
        for request in transport.requests {
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic YWxpY2U6cDphOnNz")
            #expect(request.url?.user == nil)
            #expect(request.url?.password == nil)
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }
    }

    @Test func freshCacheExpiresAndHonorsNoCacheAndNoStore() async throws {
        let transport = MediaTransport()
        var time = Date(timeIntervalSince1970: 100)
        transport.headers["Cache-Control"] = "private, max-age=60"
        transport.headers["Age"] = "10"
        let loader = MediaLoader(api: try makeAPI(transport), now: { time })
        _ = try await loader.load(reference: "/a")
        _ = try await loader.load(reference: "/a")
        #expect(transport.requests.count == 1)
        time = time.addingTimeInterval(51)
        transport.headers["Cache-Control"] = "no-cache, max-age=60"
        _ = try await loader.load(reference: "/a")
        _ = try await loader.load(reference: "/a")
        #expect(transport.requests.count == 3)
        transport.headers["Cache-Control"] = "no-store"
        transport.headers["ETag"] = "\"private\""
        _ = try await loader.load(reference: "/b")
        _ = try await loader.load(reference: "/b")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func cacheIsBoundedAndDoesNotRetainOversizedOriginals() async throws {
        let transport = MediaTransport()
        transport.headers["Cache-Control"] = "max-age=60"
        let loader = MediaLoader(api: try makeAPI(transport), byteLimit: 2)
        _ = try await loader.load(reference: "/a")
        _ = try await loader.load(reference: "/b")
        _ = try await loader.load(reference: "/a")
        _ = try await loader.load(reference: "/c")
        _ = try await loader.load(reference: "/b")
        #expect(transport.requests.count == 4)
        transport.body = Data([1, 2, 3])
        _ = try await loader.load(reference: "/large")
        _ = try await loader.load(reference: "/large")
        #expect(transport.requests.count == 6)
    }

    @Test func connectionChangesInvalidateEvenForTheSameServerAndUsername() async throws {
        let transport = MediaTransport()
        transport.headers["Cache-Control"] = "max-age=60"
        let api = try makeAPI(transport)
        let loader = MediaLoader(api: api)
        _ = try await loader.load(reference: "/a")
        api.configure(api.configuration)
        _ = try await loader.load(reference: "/a")
        #expect(transport.requests.count == 2)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func failuresAndUnexpected304CanBeRetried() async throws {
        let transport = MediaTransport()
        let loader = MediaLoader(api: try makeAPI(transport))
        transport.status = 401
        await #expect(throws: ConnectionFailure.unauthorized) { try await loader.load(reference: "/a") }
        transport.status = 304
        await #expect(throws: ConnectionFailure.invalidResponse) { try await loader.load(reference: "/a") }
        transport.status = 200
        #expect(try await loader.load(reference: "/a").data == Data([1]))
        #expect(transport.requests.count == 3)
    }

    @Test func unsafeRequestsNeverReachTransport() async throws {
        let transport = MediaTransport()
        let api = try makeAPI(transport)
        await #expect(throws: ConnectionFailure.invalidURL) {
            try await api.mediaResponse(reference: "https://other.local/a", etag: nil)
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func concurrentLoadsShareOneDownloadAndCancellationDoesNotCancelOtherConsumers() async throws {
        let transport = MediaTransport()
        transport.suspended = true
        let loader = MediaLoader(api: try makeAPI(transport))
        let first = Task { try await loader.load(reference: "/a") }
        while transport.requests.isEmpty { await Task.yield() }
        let second = Task { try await loader.load(reference: "/a") }
        await Task.yield()
        first.cancel()
        transport.resume()
        await #expect(throws: CancellationError.self) { try await first.value }
        #expect(try await second.value.data == Data([1]))
        #expect(transport.requests.count == 1)
    }

    @Test func lastConsumerCancellationCancelsTransportAndAllowsRetry() async throws {
        let transport = MediaTransport()
        transport.suspended = true
        let loader = MediaLoader(api: try makeAPI(transport))
        let task = Task { try await loader.load(reference: "/a") }
        while transport.requests.isEmpty { await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(transport.wasCancelled)
        transport.suspended = false
        #expect(try await loader.load(reference: "/a").data == Data([1]))
    }

    private func makeAPI(_ transport: MediaTransport) throws -> URLSessionAPIService {
        URLSessionAPIService(
            configuration: try ServerConnection(baseURL: base, username: "alice"),
            credentials: MediaCredentials(), transport: transport
        )
    }
}

@MainActor
private final class MediaCredentials: CredentialService {
    func password() async throws -> String? { "p:a:ss" }
    func setPassword(_ password: String?) async throws {}
}

@MainActor
private final class MediaTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var body = Data([1])
    var headers = ["Content-Type": "image/jpeg"]
    var suspended = false
    var wasCancelled = false
    private var continuation: CheckedContinuation<Void, any Error>?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if suspended {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation = $0 }
            } onCancel: {
                Task { @MainActor in
                    self.wasCancelled = true
                    self.continuation?.resume(throwing: CancellationError())
                    self.continuation = nil
                }
            }
        }
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
