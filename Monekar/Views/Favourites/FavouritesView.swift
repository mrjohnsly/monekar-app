//
//  FavouritesView.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct FavouritesView: View {
    
    @State private var viewModel: FavouritesViewModel = FavouritesViewModel()
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 4)], spacing: 4) {
                ForEach(viewModel.favourites) { image in
                    AsyncImage(url: URL(string: image.thumbnailImageURL)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                }
            }
        }
        .navigationTitle("Favourites")
        .task {
            await viewModel.fetchFavourites()
        }
    }
}
