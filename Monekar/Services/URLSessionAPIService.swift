import Foundation

enum APIError: Error {
    case unconfigured
    case insecureServer
    case invalidResponse
    case httpStatus(Int)
}

@MainActor
final class URLSessionAPIService: APIService {
    let baseURL: URL?
    private let credentials: any CredentialService
    private let session: URLSession

    init(baseURL: URL?, credentials: any CredentialService, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.session = session
    }

    func get(path: [String]) async throws -> Data {
        guard var url = baseURL else { throw APIError.unconfigured }
        guard url.scheme?.lowercased() == "https",
              url.host != nil, url.user == nil, url.password == nil else {
            throw APIError.insecureServer
        }
        for component in path {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = try await credentials.accessToken(), !token.isEmpty {
            let authorization = "Bearer " + token
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw APIError.httpStatus(response.statusCode)
        }
        return data
    }
}
