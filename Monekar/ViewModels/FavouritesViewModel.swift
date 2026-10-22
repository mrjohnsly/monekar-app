//
//  FavouritesViewModel.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation
import Observation

@Observable
final class FavouritesViewModel {
    
    var favourites: [ImageItem] = []
    var total: Int = 0
    
    func fetchFavourites() async {
        
        let username = "admin"
        let password = "admin123"
        
        var request = URLRequest(url: URL(string: "http://192.168.1.249:8080/api/v1/favourites")!)
        
        let raw = "\(username):\(password)".data(using: .utf8)!
            request.setValue("Basic \(raw.base64EncodedString())", forHTTPHeaderField: "Authorization")
            request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            print(httpResponse.statusCode)
            
            let decoded = try JSONDecoder().decode(FavouritesPage.self, from: data)
            favourites = decoded.items
            total = decoded.total
        } catch {
            print(error)
        }
    }
}
