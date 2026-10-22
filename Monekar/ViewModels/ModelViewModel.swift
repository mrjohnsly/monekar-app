//
//  ModelViewModel.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation
import Observation

@Observable
final class ModelViewModel {
    
    var albums: [Album] = []
    
    func fetchAlbums(modelID: Int) async {
        let username = "admin"
        let password = "admin123"
        
        var request = URLRequest(url: URL(string: "http://192.168.1.249:8080/api/v1/people/\(modelID)/albums")!)
        
        let raw = "\(username):\(password)".data(using: .utf8)!
            request.setValue("Basic \(raw.base64EncodedString())", forHTTPHeaderField: "Authorization")
            request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            print(httpResponse.statusCode)
            
            let decoded = try JSONDecoder().decode(AlbumsPage.self, from: data)
            albums = decoded.items
        } catch {
            print(error)
        }
    }
}
