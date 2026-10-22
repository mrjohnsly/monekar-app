//
//  ModelThumbnail.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct ModelThumbnail: View {
    
    let model: Model
    
    var body: some View {
        VStack {
            ThumbnailFrame {
                AsyncImage(url: URL(string: model.thumbnailImageURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } placeholder: {
                    ProgressView()
                }
            }
            .frame(width: 250)
            
            Text(model.name)
        }
    }
}
