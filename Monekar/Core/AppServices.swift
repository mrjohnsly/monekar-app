import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
protocol APIService {
    var baseURL: URL? { get }
    func configure(_ configuration: ServerConnection?)
    func verifyConnection(_ configuration: ServerConnection?) async throws
    func get(path: [String]) async throws -> Data
    func get(mediaReference: String) async throws -> Data
    func request(_ request: APIRequest) async throws -> Data
    var mediaSessionID: UUID? { get }
    func mediaResponse(reference: String, etag: String?) async throws -> MediaResponse
}

extension APIService {
    var mediaSessionID: UUID? { nil }

    func mediaResponse(reference: String, etag: String?) async throws -> MediaResponse {
        guard let url = URL(string: reference) else { throw ConnectionFailure.invalidURL }
        let data = try await get(mediaReference: reference)
        return MediaResponse(
            data: data,
            response: HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/octet-stream"]
            )!
        )
    }
}

@MainActor
protocol CredentialService {
    func password() async throws -> String?
    func setPassword(_ password: String?) async throws
}

@MainActor
protocol HTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

@MainActor
protocol ConnectionMetadataService {
    var configuration: ServerConnection? { get }
    func save(_ configuration: ServerConnection) throws
    func remove() throws
}

@MainActor
struct AppServices {
    let api: any APIService
    let credentials: any CredentialService
    let connectionMetadata: any ConnectionMetadataService
    let navigationSession = AppNavigationSession()
    let media: MediaLoader

    init(api: any APIService, credentials: any CredentialService, connectionMetadata: any ConnectionMetadataService) {
        self.api = api
        self.credentials = credentials
        self.connectionMetadata = connectionMetadata
        media = MediaLoader(api: api)
    }
}
