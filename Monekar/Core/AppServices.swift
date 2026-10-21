import Foundation

@MainActor
protocol APIService {
    var baseURL: URL? { get }
    func get(path: [String]) async throws -> Data
}

@MainActor
protocol CredentialService {
    func accessToken() async throws -> String?
    func setAccessToken(_ token: String?) async throws
}

@MainActor
struct AppServices {
    let api: any APIService
    let credentials: any CredentialService
}
