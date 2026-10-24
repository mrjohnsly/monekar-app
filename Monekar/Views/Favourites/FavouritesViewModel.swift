//
//  FavouritesViewModel.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import Foundation
import Observation

@Observable
@MainActor
final class FavouritesViewModel {
    
    private let apiService: any FavouritesAPIService
    
    var favourites: [ImageItem] = []
    var total: Int = 0
    
    init(apiService: any FavouritesAPIService = URLSessionFavouritesAPIService()) {
        self.apiService = apiService
    }
    
    func fetchFavourites() async {
        do {
            let page = try await apiService.fetchFavourites()
            favourites = page.items
            total = page.total
        } catch {
            print(error)
        }
    }
}
