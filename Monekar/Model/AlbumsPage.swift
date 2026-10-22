//
//  AlbumsPage.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct AlbumsPage: Decodable {
    let items: [Album]
    let total: Int
    let limit: Int
    let offset: Int
}
