import Foundation

// The configured base URL is the server installation root (including any proxy prefix),
// not /api/v1. Health is public; all v1 routes use the authenticated request transport.
extension APIService {
    func health() async throws -> MonekarAPI.Health {
        try decode(await request(APIRequest(path: ["health"])))
    }

    func people(limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Person> {
        try await page(["people"], limit: limit, offset: offset)
    }

    func person(id: Int) async throws -> MonekarAPI.Person {
        try await json(["people", String(id)])
    }

    func albums(personID: Int, limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Album> {
        try await page(["people", String(personID), "albums"], limit: limit, offset: offset)
    }

    func images(personID: Int, limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Image> {
        try await page(["people", String(personID), "images"], limit: limit, offset: offset)
    }

    func album(id: Int) async throws -> MonekarAPI.Album {
        try await json(["albums", String(id)])
    }

    func images(albumID: Int, limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Image> {
        try await page(["albums", String(albumID), "images"], limit: limit, offset: offset)
    }

    func favourites(limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Image> {
        try await page(["favourites"], limit: limit, offset: offset)
    }

    func setFavourite(imageID: Int, isFavourite: Bool) async throws -> MonekarAPI.Image {
        try await json(
            ["images", String(imageID), "favourite"],
            method: isFavourite ? .put : .delete
        )
    }

    func tags(limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Tag> {
        try await page(["tags"], limit: limit, offset: offset)
    }

    func images(tagID: Int, limit: Int? = nil, offset: Int? = nil) async throws -> MonekarAPI.Page<MonekarAPI.Image> {
        try await page(["tags", String(tagID), "images"], limit: limit, offset: offset)
    }

    func tags(imageID: Int) async throws -> [MonekarAPI.Tag] {
        try await json(["images", String(imageID), "tags"])
    }

    func addTag(imageID: Int, name: String) async throws -> MonekarAPI.Tag {
        return try await json(
            ["images", String(imageID), "tags"], method: .post,
            body: JSONEncoder().encode(["name": name])
        )
    }

    func removeTag(imageID: Int, tagID: Int) async throws {
        _ = try await request(APIRequest(
            path: ["api", "v1", "images", String(imageID), "tags", String(tagID)],
            method: .delete
        ))
    }

    func scanStatus() async throws -> MonekarAPI.ScanStatus {
        try await json(["library", "scan-status"])
    }

    func rescan() async throws -> MonekarAPI.ScanReport {
        try await json(["library", "rescan"], method: .post)
    }

    func thumbnail(imageID: Int, size: MonekarAPI.ThumbnailSize? = nil) async throws -> Data {
        let query = size.map { [URLQueryItem(name: "size", value: String($0.rawValue))] } ?? []
        return try await request(APIRequest(
            path: ["api", "v1", "images", String(imageID), "thumbnail"], queryItems: query
        ))
    }

    func original(imageID: Int) async throws -> Data {
        try await request(APIRequest(path: ["api", "v1", "images", String(imageID), "original"]))
    }

    func thumbnail(albumID: Int) async throws -> Data {
        try await request(APIRequest(path: ["api", "v1", "albums", String(albumID), "thumbnail"]))
    }

    func thumbnail(personID: Int) async throws -> Data {
        try await request(APIRequest(path: ["api", "v1", "people", String(personID), "thumbnail"]))
    }

    // Callers opt into walking pages; fetching a single page never downloads the whole library.
    func allPages<Item>(
        limit: Int = 50,
        offset: Int = 0,
        fetch: (Int, Int) async throws -> MonekarAPI.Page<Item>
    ) async throws -> [Item] {
        try validatePagination(limit: limit, offset: offset)
        var items: [Item] = []
        var nextOffset = offset
        while true {
            try Task.checkCancellation()
            let page = try await fetch(limit, nextOffset)
            guard page.total >= 0, (1...500).contains(page.limit),
                  page.offset == nextOffset, page.items.count <= page.limit else {
                throw ConnectionFailure.invalidResponse
            }
            items.append(contentsOf: page.items)
            let (next, overflow) = page.offset.addingReportingOverflow(page.limit)
            guard !overflow else { throw ConnectionFailure.invalidResponse }
            if next >= page.total { return items }
            guard !page.items.isEmpty else { throw ConnectionFailure.invalidResponse }
            nextOffset = next
        }
    }

    private func page<Item>(
        _ path: [String], limit: Int?, offset: Int?
    ) async throws -> MonekarAPI.Page<Item> {
        try validatePagination(limit: limit, offset: offset)
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        return try decode(await request(APIRequest(path: ["api", "v1"] + path, queryItems: query)))
    }

    private func json<Response: Decodable>(
        _ path: [String], method: HTTPMethod = .get, body: Data? = nil
    ) async throws -> Response {
        try decode(await request(APIRequest(path: ["api", "v1"] + path, method: method, body: body)))
    }

    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ConnectionFailure.decodingFailed
        }
    }

    private func validatePagination(limit: Int?, offset: Int?) throws {
        if let limit, !(1...500).contains(limit) { throw ConnectionFailure.invalidPagination }
        if let offset, offset < 0 { throw ConnectionFailure.invalidPagination }
    }
}
