//
//  AlbumView.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct AlbumView: View {
    
    @State private var viewModel: AlbumViewModel = AlbumViewModel()
    
    let album: Album
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 4)], spacing: 4) {
                ForEach(viewModel.images) { image in
                    AsyncImage(url: URL(string: image.thumbnailImageURL)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        ProgressView()
                    }
                    .task {
                        if image.id == viewModel.images.last?.id {
                            await viewModel.fetchImages(albumID: album.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(album.name)
        .task {
            await viewModel.fetchImages(albumID: album.id)
        }
    }
}
