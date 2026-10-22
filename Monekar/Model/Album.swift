//
//  Album.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct Album: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: Int
    let personID: Int
    let name: String
    let date: String?
    let models: [String]?
    let photographer: String?
    let imageCount: Int
    let thumbnailURL: String
    
    var thumbnailImageURL: String {
        "http://192.168.1.249:8080\(self.thumbnailURL)"
    }
}
