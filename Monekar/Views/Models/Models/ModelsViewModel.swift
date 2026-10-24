//
//  ModelsViewModel.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class ModelsViewModel {

    var models: [Model] = []
    private var offset = 0
    private var isLoading = false
    private var hasMore = true

    func fetchModels() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        defer { isLoading = false }

        let username = "admin"
        let password = "admin123"
        
        var request = URLRequest(url: URL(string: "http://192.168.1.249:8080/api/v1/people?offset=\(offset)")!)
        
        let raw = "\(username):\(password)".data(using: .utf8)!
            request.setValue("Basic \(raw.base64EncodedString())", forHTTPHeaderField: "Authorization")
            request.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                throw URLError(.badServerResponse)
            }
            
            let decoded = try JSONDecoder().decode(ModelsPage.self, from: data)
            models.append(contentsOf: decoded.items)
            offset = decoded.offset + decoded.items.count
            hasMore = !decoded.items.isEmpty && offset < decoded.total
        } catch {
            print(error)
        }
    }
}
