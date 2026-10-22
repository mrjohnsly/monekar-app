#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor
enum ModelNavigationTestServices {
    static func make() -> AppServices {
        AppServices(
            api: ModelNavigationTestAPI(),
            credentials: ModelNavigationTestCredentials(),
            connectionMetadata: ModelNavigationTestMetadata()
        )
    }
}

@MainActor
private final class ModelNavigationTestAPI: APIService {
    var baseURL: URL? = URL(string: "https://navigation-test.invalid")

    func configure(_ configuration: ServerConnection?) { baseURL = configuration?.baseURL }
    func verifyConnection(_ configuration: ServerConnection?) async throws {}
    func get(path: [String]) async throws -> Data { throw ConnectionFailure.invalidURL }
    func get(mediaReference: String) async throws -> Data { throw ConnectionFailure.invalidURL }

    func request(_ request: APIRequest) async throws -> Data {
        let person = #"{"id":7,"name":"Navigation model","albumCount":0,"imageCount":0,"thumbnailURL":"/thumbnail"}"#
        switch request.path {
        case ["api", "v1", "people"]:
            return Data("""
            {"items":[\(person)],"total":1,"limit":50,"offset":0}
            """.utf8)
        case ["api", "v1", "people", "7"]:
            return Data(person.utf8)
        case ["api", "v1", "people", "7", "albums"], ["api", "v1", "people", "7", "images"]:
            return Data(#"{"items":[],"total":0,"limit":50,"offset":0}"#.utf8)
        default:
            throw ConnectionFailure.invalidURL
        }
    }

    func mediaResponse(reference: String, etag: String?) async throws -> MediaResponse {
        MediaResponse(
            data: Data(#"<svg xmlns="http://www.w3.org/2000/svg"/>"#.utf8),
            response: HTTPURLResponse(
                url: URL(string: "https://navigation-test.invalid/thumbnail")!,
                statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/svg+xml"]
            )!
        )
    }
}

@MainActor
private final class ModelNavigationTestCredentials: CredentialService {
    func password() async throws -> String? { "ui-test-value" }
    func setPassword(_ password: String?) async throws {}
}

@MainActor
private final class ModelNavigationTestMetadata: ConnectionMetadataService {
    var configuration: ServerConnection? = try? ServerConnection(
        serverURL: "https://navigation-test.invalid", username: "ui-test"
    )
    func save(_ configuration: ServerConnection) throws { self.configuration = configuration }
    func remove() throws { configuration = nil }
}
#endif
