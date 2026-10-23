//
//  AlbumThumbnail.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct AlbumThumbnail: View {
    
    let album: Album
    
    var body: some View {
        VStack {
            ThumbnailFrame {
                AsyncImage(url: URL(string: album.thumbnailImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
            }
            .frame(width: 250)
            
            Text(album.name)
        }
    }
}
