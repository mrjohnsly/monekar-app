//
//  AlbumViewModel.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class AlbumViewModel {
    
    var images: [ImageItem] = []
    private var offset = 0
    private var isLoading = false
    private var hasMore = true
    
    func fetchImages(albumID: Int) async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        
        let username = "admin"
        let password = "admin123"
        
        var request = URLRequest(url: URL(string: "http://192.168.1.249:8080/api/v1/albums/\(albumID)/images?offset=\(offset)")!)
        
        let raw = "\(username):\(password)".data(using: .utf8)!
            request.setValue("Basic \(raw.base64EncodedString())", forHTTPHeaderField: "Authorization")
            request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            
            print(httpResponse.statusCode)
            
            let decoded = try JSONDecoder().decode(ImagesPage.self, from: data)
            images.append(contentsOf: decoded.items)
            offset = (decoded.offset ?? offset) + decoded.items.count
            hasMore = !decoded.items.isEmpty && (decoded.total.map { offset < $0 } ?? true)
        } catch {
            print(error)
        }
    }
}
