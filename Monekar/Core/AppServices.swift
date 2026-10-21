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
}
