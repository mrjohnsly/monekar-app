import Foundation

protocol FavouritesAPIService {
    func fetchFavourites() async throws -> FavouritesPage
}

struct URLSessionFavouritesAPIService: FavouritesAPIService {
    private let session: URLSession
    private let baseURL: String
    private let username: String
    private let password: String
    
    init(
        session: URLSession = .shared,
        baseURL: String = "http://192.168.1.249:8080",
        username: String = "admin",
        password: String = "admin123"
    ) {
        self.session = session
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }
    
    func fetchFavourites() async throws -> FavouritesPage {
        guard let baseURL = URL(string: baseURL),
              let scheme = baseURL.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              baseURL.host != nil else {
            throw URLError(.badURL)
        }
        
        let url = baseURL.appending(path: "api/v1/favourites")
        var request = URLRequest(url: url)
        let credentials = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        return try JSONDecoder().decode(FavouritesPage.self, from: data)
    }
}
