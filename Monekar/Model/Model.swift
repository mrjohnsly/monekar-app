//
//  Model.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct Model: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let albumCount: Int
    let imageCount: Int
    let thumbnailURL: String
    
    var thumbnailImageURL: String {
        "http://192.168.1.249:8080\(self.thumbnailURL)"
    }
}
