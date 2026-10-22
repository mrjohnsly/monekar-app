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
            AsyncImage(url: URL(string: model.thumbnailImageURL)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 250)
            } placeholder: {
                ProgressView()
            }
            
            Text(model.name)
        }
    }
}
