import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
final class URLSessionAPIService: APIService {
    private(set) var configuration: ServerConnection?
    private let credentials: any CredentialService
    private let transport: any HTTPTransport

    var baseURL: URL? { configuration?.baseURL }

    init(
        configuration: ServerConnection?,
        credentials: any CredentialService,
        transport: (any HTTPTransport)? = nil
    ) {
        self.configuration = configuration
        self.credentials = credentials
        self.transport = transport ?? URLSessionHTTPTransport()
    }

    func configure(_ configuration: ServerConnection?) {
        self.configuration = configuration
    }

    func verifyConnection(_ configuration: ServerConnection?) async throws {
        guard let configuration else { throw ConnectionFailure.invalidURL }
        let url = configuration.baseURL.appendingPathComponent("health")
        _ = try await perform(url: url, configuration: configuration, authenticated: false)
    }

    func get(path: [String]) async throws -> Data {
        guard let configuration else { throw ConnectionFailure.invalidURL }
        let url = path.reduce(configuration.baseURL) { $0.appendingPathComponent($1) }
        return try await perform(url: url, configuration: configuration, authenticated: true)
    }

    func request(_ apiRequest: APIRequest) async throws -> Data {
        guard let configuration else { throw ConnectionFailure.invalidURL }
        let url = apiRequest.path.reduce(configuration.baseURL) { $0.appendingPathComponent($1) }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            throw ConnectionFailure.invalidURL
        }
        if !apiRequest.queryItems.isEmpty { components.queryItems = apiRequest.queryItems }
        guard let requestURL = components.url else { throw ConnectionFailure.invalidURL }
        let isHealth = apiRequest.path == ["health"] && apiRequest.method == .get
        return try await perform(
            url: requestURL, configuration: configuration, authenticated: !isHealth,
            method: apiRequest.method, body: apiRequest.body
        )
    }

    func get(mediaReference: String) async throws -> Data {
        guard let configuration,
              let url = URL(string: mediaReference, relativeTo: configuration.baseURL)?.absoluteURL else {
            throw ConnectionFailure.invalidURL
        }
        let authenticated = Self.sameOrigin(url, configuration.baseURL)
        return try await perform(url: url, configuration: configuration, authenticated: authenticated)
    }

    private func perform(
        url: URL,
        configuration: ServerConnection,
        authenticated: Bool,
        method: HTTPMethod = .get,
        body: Data? = nil
    ) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              url.user == nil, url.password == nil else {
            throw ConnectionFailure.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated {
            guard let password = try await credentials.password(), !password.isEmpty else {
                throw ConnectionFailure.missingPassword
            }
            let userPassword = "\(configuration.username):\(password)"
            request.setValue(
                "Basic \(Data(userPassword.utf8).base64EncodedString())",
                forHTTPHeaderField: "Authorization"
            )
        }

        do {
            let (data, response) = try await transport.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw ConnectionFailure.invalidResponse
            }
            if response.statusCode == 401 { throw ConnectionFailure.unauthorized }
            guard (200..<300).contains(response.statusCode) else {
                throw ConnectionFailure.serverRejected(response.statusCode)
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let failure as ConnectionFailure {
            throw failure
        } catch let error as URLError {
            switch error.code {
            case .cancelled:
                throw CancellationError()
            case .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot,
                 .secureConnectionFailed:
                throw ConnectionFailure.certificateTrust
            case .notConnectedToInternet where Self.isLocalHost(configuration.baseURL.host):
                throw ConnectionFailure.localNetworkAccess
            default:
                throw ConnectionFailure.unreachable
            }
        } catch {
            throw ConnectionFailure.unreachable
        }
    }

    private static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let lhs = URLComponents(url: first, resolvingAgainstBaseURL: true),
              let rhs = URLComponents(url: second, resolvingAgainstBaseURL: true) else {
            return false
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && effectivePort(lhs) == effectivePort(rhs)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
    }

    private static func isLocalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local")
            || host == "::1" || host.hasPrefix("fe80:") || host.hasPrefix("fc") || host.hasPrefix("fd") {
            return true
        }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || octets[0] == 127
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 169 && octets[1] == 254)
            || (octets[0] == 100 && (64...127).contains(octets[1]))
    }
}

@MainActor
private final class URLSessionHTTPTransport: HTTPTransport {
    private let session: URLSession

    init() {
        session = URLSession(
            configuration: .default,
            delegate: SameOriginRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

private final class SameOriginRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let originalURL = task.originalRequest?.url,
              let redirectedURL = request.url,
              redirectedURL.user == nil, redirectedURL.password == nil,
              Self.sameOrigin(originalURL, redirectedURL) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private static func sameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let lhs = URLComponents(url: first, resolvingAgainstBaseURL: true),
              let rhs = URLComponents(url: second, resolvingAgainstBaseURL: true) else {
            return false
        }
        func port(_ components: URLComponents) -> Int? {
            components.port ?? (components.scheme?.lowercased() == "https" ? 443 : 80)
        }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased()
            && port(lhs) == port(rhs)
    }
}
