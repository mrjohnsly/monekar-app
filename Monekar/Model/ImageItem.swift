//
//  ImageItem 2.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct ImageItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: Int
    let albumID: Int
    let fileName: String
    let width: Int
    let height: Int
    let format: String
    let byteSize: Int
    let isFavourite: Bool
    let tags: [String]?
    let thumbnailURL: String
    let originalURL: String

    var thumbnailImageURL: String {
        "http://192.168.1.249:8080\(thumbnailURL)"
    }

    var originalImageURL: String {
        "http://192.168.1.249:8080\(originalURL)"
    }
    
    var aspectRatio: CGFloat {
        width > 0 && height > 0 ? CGFloat(width) / CGFloat(height) : 1
    }
}
