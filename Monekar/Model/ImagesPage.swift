//
//  ImagesPage.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct ImagesPage: Decodable {
    let items: [ImageItem]
    let total: Int?
    let limit: Int?
    let offset: Int?
}
