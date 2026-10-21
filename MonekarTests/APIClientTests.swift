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
struct APIClientTests {
    @Test func decodesPeopleAndPreservesRelativeMediaReferences() async throws {
        let (api, transport) = try client()
        transport.json = Self.page(Self.personJSON)
        let page = try await api.people()
        #expect(page.items.first?.id == 7)
        #expect(page.items.first?.name == "Person")
        #expect(page.items.first?.albumCount == 2)
        #expect(page.items.first?.imageCount == 3)
        #expect(page.items.first?.thumbnailURL == "/api/v1/people/7/thumbnail")
        #expect(page.total == 1)
        #expect(page.limit == 50)
        #expect(page.offset == 0)
        #expect(transport.requests.last?.url?.absoluteString == "https://server.local/api/v1/people")
    }

    @Test func decodesNullableAndPresentAlbumMetadata() async throws {
        let (api, transport) = try client()
        transport.json = Self.albumJSON
        let empty = try await api.album(id: 8)
        #expect(empty.personID == 7)
        #expect(empty.date == nil)
        #expect(empty.models == nil)
        #expect(empty.photographer == nil)

        transport.json = Self.albumJSON
            .replacingOccurrences(of: "\"date\":null,", with: "")
            .replacingOccurrences(of: "\"models\":null,", with: "")
            .replacingOccurrences(of: "\"photographer\":null,", with: "")
        #expect(try await api.album(id: 8) == empty)

        transport.json = """
        {"id":8,"personID":7,"name":"Site - Set","date":"2026-10-21",
        "models":"Person","photographer":"Photographer","imageCount":1,
        "thumbnailURL":"/api/v1/albums/8/thumbnail"}
        """
        let album = try await api.album(id: 8)
        #expect(album.date == "2026-10-21")
        #expect(album.models == "Person")
        #expect(album.photographer == "Photographer")
    }

    @Test func decodesOptionalDimensionsLargeSizesAndEmbeddedTags() async throws {
        let (api, transport) = try client()
        transport.json = Self.page(Self.imageJSON)
        let image = try #require(await api.images(albumID: 8).items.first)
        #expect(image.byteSize == 5_000_000_000)
        #expect(image.width == nil)
        #expect(image.height == nil)
        #expect(image.tags == [MonekarAPI.Tag(id: 10, name: "Summer")])
        #expect(image.originalURL == "/api/v1/images/9/original")
        #expect(image.format == "jpeg")
        #expect(image.fileName == "image.jpg")
        #expect(image.isFavourite)

        transport.json = Self.page(Self.imageJSON.replacingOccurrences(
            of: "\"height\":null", with: "\"height\":1024,\"width\":768"
        ))
        let dimensions = try #require(await api.images(albumID: 8).items.first)
        #expect(dimensions.width == 768)
        #expect(dimensions.height == 1024)
    }

    @Test func scanStatusPreservesUnixSecondsAndNullFields() async throws {
        let (api, transport) = try client()
        transport.json = Self.scanStatusJSON
        let status = try await api.scanStatus()
        #expect(status.state == .running)
        #expect(status.phase == .indexingAlbumCovers)
        #expect(status.percentage == 12.5)
        #expect(status.startedAt == 1_792_620_000.25)
        #expect(status.lastCompletedAt == nil)
        #expect(status.lastError == nil)
        #expect(status.remainingImages == 7)
        #expect(transport.requests.last?.url?.path == "/api/v1/library/scan-status")

        transport.json = Self.scanStatusJSON
            .replacingOccurrences(of: "\"running\"", with: "\"failed\"")
            .replacingOccurrences(of: "\"indexing album covers\"", with: "\"failed\"")
            .replacingOccurrences(of: "\"lastCompletedAt\":null", with: "\"lastCompletedAt\":1700000000")
            .replacingOccurrences(of: "\"lastError\":null", with: "\"lastError\":\"Unavailable\"")
        let failed = try await api.scanStatus()
        #expect(failed.state == .failed)
        #expect(failed.phase == .failed)
        #expect(failed.lastCompletedAt == 1_700_000_000)
        #expect(failed.lastError == "Unavailable")
    }

    @Test func rescanDecodesReportAndSafeIssues() async throws {
        let (api, transport) = try client()
        transport.json = """
        {"people":1,"albums":2,"images":3,"ignoredFiles":4,"removedImages":5,
        "pruned":false,"issues":[{"reason":"Unreadable entry"}]}
        """
        let report = try await api.rescan()
        #expect(report.people == 1)
        #expect(report.albums == 2)
        #expect(report.images == 3)
        #expect(report.ignoredFiles == 4)
        #expect(report.removedImages == 5)
        #expect(!report.pruned)
        #expect(report.issues.map(\.reason) == ["Unreadable entry"])
        #expect(transport.requests.last?.url?.path == "/api/v1/library/rescan")
        #expect(transport.requests.last?.httpMethod == "POST")
    }

    @Test func buildsEveryJSONGetRoute() async throws {
        let (api, transport) = try client(baseURL: "https://server.local/monekar")
        transport.json = Self.personJSON
        _ = try await api.person(id: 7)
        transport.json = Self.page(Self.albumJSON)
        _ = try await api.albums(personID: 7, limit: 25, offset: 50)
        transport.json = Self.page(Self.imageJSON)
        _ = try await api.images(personID: 7)
        _ = try await api.images(albumID: 8)
        _ = try await api.favourites()
        _ = try await api.images(tagID: 10)
        transport.json = Self.page(Self.tagJSON)
        _ = try await api.tags()
        transport.json = "[\(Self.tagJSON)]"
        #expect(try await api.tags(imageID: 9) == [MonekarAPI.Tag(id: 10, name: "Summer")])

        #expect(transport.requests.compactMap { $0.url?.path } == [
            "/monekar/api/v1/people/7", "/monekar/api/v1/people/7/albums",
            "/monekar/api/v1/people/7/images", "/monekar/api/v1/albums/8/images",
            "/monekar/api/v1/favourites", "/monekar/api/v1/tags/10/images",
            "/monekar/api/v1/tags", "/monekar/api/v1/images/9/tags",
        ])
        #expect(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        let url = try #require(transport.requests[1].url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems)
        #expect(query == [
            URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "offset", value: "50"),
        ])
        #expect(transport.requests[2].url?.query == nil)
    }

    @Test func mutationsUseCorrectVerbsAndJSONBody() async throws {
        let (api, transport) = try client()
        transport.json = Self.imageJSON
        #expect(try await api.setFavourite(imageID: 9, isFavourite: true).isFavourite)
        transport.json = Self.imageJSON.replacingOccurrences(of: "\"isFavourite\":true", with: "\"isFavourite\":false")
        #expect(try await !api.setFavourite(imageID: 9, isFavourite: false).isFavourite)
        transport.json = Self.tagJSON
        let name = "Summer \"Holiday\"\n☀"
        #expect(try await api.addTag(imageID: 9, name: name).name == "Summer")
        transport.statusCode = 204
        transport.json = ""
        try await api.removeTag(imageID: 9, tagID: 10)

        #expect(transport.requests.map(\.httpMethod) == ["PUT", "DELETE", "POST", "DELETE"])
        #expect(transport.requests.compactMap { $0.url?.path } == [
            "/api/v1/images/9/favourite", "/api/v1/images/9/favourite",
            "/api/v1/images/9/tags", "/api/v1/images/9/tags/10",
        ])
        let post = transport.requests[2]
        #expect(post.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONDecoder().decode([String: String].self, from: #require(post.httpBody)) == ["name": name])
        #expect(transport.requests[0].httpBody == nil)
        #expect(transport.requests[3].httpBody == nil)
    }

    @Test func paginationUsesReturnedLimitAndStopsAtTotal() async throws {
        let (api, transport) = try client()
        transport.respond = { request in
            let offset = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?
                .queryItems?.first { $0.name == "offset" }?.value
            let position = Int(offset!)!
            let items = Array(repeating: Self.personJSON, count: min(2, 5 - position)).joined(separator: ",")
            return Self.page(items, total: 5, limit: 2, offset: position)
        }
        let people = try await api.allPages(limit: 10) { limit, offset in
            try await api.people(limit: limit, offset: offset)
        }
        #expect(people.count == 5)
        #expect(transport.requests.map { $0.url?.query } == [
            "limit=10&offset=0", "limit=10&offset=2", "limit=10&offset=4",
        ])
    }

    @Test func paginationSupportsStartingOffsetAndAnEmptyLibrary() async throws {
        let (api, transport) = try client()
        transport.json = Self.page(Self.personJSON, total: 51, offset: 50)
        let remaining = try await api.allPages(offset: 50) { limit, offset in
            try await api.people(limit: limit, offset: offset)
        }
        #expect(remaining.count == 1)
        #expect(transport.requests.count == 1)
        transport.json = Self.page("", total: 0)
        let empty = try await api.allPages { limit, offset in
            try await api.people(limit: limit, offset: offset)
        }
        #expect(empty.isEmpty)
        #expect(transport.requests.count == 2)
    }

    @Test(arguments: [0, -1, 501])
    func invalidLimitsNeverReachTheNetwork(_ limit: Int) async throws {
        let (api, transport) = try client()
        await #expect(throws: ConnectionFailure.invalidPagination) { try await api.people(limit: limit) }
        #expect(transport.requests.isEmpty)
    }

    @Test func invalidOffsetNeverReachesTheNetwork() async throws {
        let (api, transport) = try client()
        await #expect(throws: ConnectionFailure.invalidPagination) { try await api.tags(offset: -1) }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [
        #"{"items":[],"total":5,"limit":0,"offset":0}"#,
        #"{"items":[],"total":5,"limit":1,"offset":0}"#,
        #"{"items":[],"total":5,"limit":1,"offset":1}"#,
        #"{"items":[],"total":-1,"limit":1,"offset":0}"#,
    ])
    func malformedPagesDoNotLoop(_ json: String) async throws {
        let (api, transport) = try client()
        transport.json = json
        await #expect(throws: ConnectionFailure.invalidResponse) {
            try await api.allPages { limit, offset in try await api.people(limit: limit, offset: offset) }
        }
        #expect(transport.requests.count == 1)
    }

    @Test func paginationPropagatesLaterPageFailure() async throws {
        let (api, transport) = try client()
        transport.json = Self.page(Self.personJSON, total: 3, limit: 1)
        transport.respond = { request in
            if request.url?.query?.contains("offset=1") == true { throw URLError(.networkConnectionLost) }
            return Self.page(Self.personJSON, total: 3, limit: 1)
        }
        await #expect(throws: ConnectionFailure.unreachable) {
            try await api.allPages { limit, offset in try await api.people(limit: limit, offset: offset) }
        }
        #expect(transport.requests.count == 2)
    }

    @Test(arguments: MonekarAPI.ThumbnailSize.allCases)
    func thumbnailSizesAreRestrictedToServerValues(_ size: MonekarAPI.ThumbnailSize) async throws {
        let (api, transport) = try client()
        let binary = Data([0xff, 0xd8, 0x00, 0xff])
        transport.binary = binary
        #expect(try await api.thumbnail(imageID: 9, size: size) == binary)
        #expect(transport.requests.last?.url?.absoluteString
            == "https://server.local/api/v1/images/9/thumbnail?size=\(size.rawValue)")
    }

    @Test func binaryMediaAndSVGPlaceholdersAreNotJSONDecoded() async throws {
        let (api, transport) = try client()
        transport.binary = Data([0xff, 0xd8])
        #expect(try await api.thumbnail(imageID: 9) == transport.binary)
        #expect(try await api.original(imageID: 9) == transport.binary)
        transport.binary = Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)
        #expect(try await api.thumbnail(albumID: 8) == transport.binary)
        #expect(try await api.thumbnail(personID: 7) == transport.binary)
        #expect(transport.requests.compactMap { $0.url?.path } == [
            "/api/v1/images/9/thumbnail", "/api/v1/images/9/original",
            "/api/v1/albums/8/thumbnail", "/api/v1/people/7/thumbnail",
        ])
        #expect(transport.requests.allSatisfy { $0.url?.query == nil })
    }

    @Test func healthIsPublicAndProtectedRequestsAreAuthenticated() async throws {
        let (api, transport) = try client()
        transport.json = #"{"status":"ok"}"#
        #expect(try await api.health().status == "ok")
        #expect(transport.requests.last?.url?.path == "/health")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)

        transport.json = Self.personJSON
        _ = try await api.person(id: 7)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization")
            == "Basic \(Data("alice:test-password".utf8).base64EncodedString())")
    }

    @Test func missingPasswordIsExplicitAndPublicHealthStillWorks() async throws {
        let (api, transport) = try client(password: nil)
        await #expect(throws: ConnectionFailure.missingPassword) { try await api.people() }
        #expect(transport.requests.isEmpty)
        transport.json = #"{"status":"ok"}"#
        #expect(try await api.health().status == "ok")
    }

    @Test(arguments: [
        "/api/v1/images/9/original", "https://server.local/api/v1/images/9/original",
        "https://SERVER.local:443/api/v1/images/9/original",
    ])
    func sameOriginMediaUsesCredentials(_ reference: String) async throws {
        let (api, transport) = try client(baseURL: "https://server.local/monekar")
        transport.binary = Data([1, 2, 3])
        #expect(try await api.get(mediaReference: reference) == transport.binary)
        #expect(transport.requests.last?.url?.path == "/api/v1/images/9/original")
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") != nil)
    }

    @Test(arguments: [
        "https://other.local/image", "//other.local/image",
        "http://server.local/image", "https://server.local:444/image",
    ])
    func credentialsNeverCrossOrigins(_ reference: String) async throws {
        let (api, transport) = try client()
        _ = try await api.get(mediaReference: reference)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test(arguments: [
        "file:///etc/passwd", "https://" + "alice" + ":" + "password" + "@server.local/image",
        "data:text/plain,hello",
    ])
    func invalidMediaReferencesAreRejected(_ reference: String) async throws {
        let (api, transport) = try client()
        await #expect(throws: ConnectionFailure.invalidURL) { try await api.get(mediaReference: reference) }
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [400, 401, 404, 409, 503, 500, 302])
    func statusFailuresRemainDistinguishable(_ status: Int) async throws {
        let (api, transport) = try client()
        transport.statusCode = status
        let expected: ConnectionFailure = status == 401 ? .unauthorized : .serverRejected(status)
        await #expect(throws: expected) { try await api.rescan() }
    }

    @Test(arguments: ["", "not JSON", "{}", #"{"id":"wrong type"}"#])
    func invalidJSONIsAnExplicitDecodingFailure(_ json: String) async throws {
        let (api, transport) = try client()
        transport.json = json
        await #expect(throws: ConnectionFailure.decodingFailed) { try await api.person(id: 7) }
    }

    @Test func transportAndNonHTTPFailuresAreExplicit() async throws {
        let (api, transport) = try client()
        transport.error = URLError(.timedOut)
        await #expect(throws: ConnectionFailure.unreachable) { try await api.people() }
        transport.error = nil
        transport.nonHTTP = true
        await #expect(throws: ConnectionFailure.invalidResponse) { try await api.people() }
        api.configure(nil)
        await #expect(throws: ConnectionFailure.invalidURL) { try await api.people() }
    }

    @Test func cancellationIsNotReportedAsNetworkOrDecodingFailure() async throws {
        let (api, transport) = try client()
        transport.error = CancellationError()
        await #expect(throws: CancellationError.self) { try await api.people() }
        transport.error = URLError(.cancelled)
        await #expect(throws: CancellationError.self) { try await api.people() }
    }

    private func client(
        baseURL: String = "https://server.local", password: String? = "test-password"
    ) throws -> (URLSessionAPIService, RecordingTransport) {
        let transport = RecordingTransport()
        return (
            URLSessionAPIService(
                configuration: try ServerConnection(serverURL: baseURL, username: "alice"),
                credentials: APITestCredentials(value: password), transport: transport
            ),
            transport
        )
    }

    private static let personJSON = """
    {"id":7,"name":"Person","albumCount":2,"imageCount":3,"thumbnailURL":"/api/v1/people/7/thumbnail"}
    """
    private static let albumJSON = """
    {"id":8,"personID":7,"name":"Album","date":null,"models":null,"photographer":null,
    "imageCount":1,"thumbnailURL":"/api/v1/albums/8/thumbnail"}
    """
    private static let tagJSON = #"{"id":10,"name":"Summer"}"#
    private static let imageJSON = """
    {"id":9,"albumID":8,"fileName":"image.jpg","format":"jpeg","byteSize":5000000000,
    "height":null,"thumbnailURL":"/api/v1/images/9/thumbnail","originalURL":"/api/v1/images/9/original",
    "isFavourite":true,"tags":[{"id":10,"name":"Summer"}]}
    """
    private static let scanStatusJSON = """
    {"state":"running","phase":"indexing album covers","discoveredPeople":3,"indexedPeople":2,
    "discoveredImages":8,"scannedImages":1,"remainingImages":7,"percentage":12.5,
    "startedAt":1792620000.25,"lastCompletedAt":null,"lastError":null}
    """

    private static func page(_ items: String, total: Int = 1, limit: Int = 50, offset: Int = 0) -> String {
        #"{"items":[\#(items)],"total":\#(total),"limit":\#(limit),"offset":\#(offset)}"#
    }
}

@MainActor
private final class RecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var json = ""
    var binary: Data?
    var statusCode = 200
    var error: (any Error)?
    var nonHTTP = false
    var respond: ((URLRequest) throws -> String)?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        if let error { throw error }
        let data = try respond.map { Data(try $0(request).utf8) } ?? binary ?? Data(json.utf8)
        if nonHTTP {
            return (data, URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil))
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private final class APITestCredentials: CredentialService {
    var value: String?

    init(value: String?) { self.value = value }
    func password() async throws -> String? { value }
    func setPassword(_ password: String?) async throws { value = password }
}
