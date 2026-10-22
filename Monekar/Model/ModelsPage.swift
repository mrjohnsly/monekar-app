//
//  ModelsPage.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation

struct ModelsPage: Decodable {
    let items: [Model]
    let total: Int
    let limit: Int
    let offset: Int
}
