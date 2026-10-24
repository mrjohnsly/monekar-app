//
//  ModelView.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct ModelView: View {
    
    @State private var viewModel: ModelViewModel = ModelViewModel()
    
    let model: Model
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(viewModel.albums) { album in
                    NavigationLink(value: album) {
                        AlbumThumbnail(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .navigationDestination(for: Album.self) { album in
                AlbumView(album: album)
                    .navigationTitle(album.name)
            }
            .navigationTitle(model.name)
        }
        .task {
            await viewModel.fetchAlbums(modelID: model.id)
        }
    }
}
