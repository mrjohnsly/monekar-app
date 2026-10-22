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
            AsyncImage(url: URL(string: album.thumbnailImageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250)
            } placeholder: {
                ProgressView()
            }
            
            Text(album.name)
        }
    }
}
