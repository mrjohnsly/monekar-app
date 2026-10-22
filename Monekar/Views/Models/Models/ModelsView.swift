//
//  ModelsView.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct ModelsView: View {
    @State private var viewModel = ModelsViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                ForEach(viewModel.models) { model in
                    NavigationLink(value: model) {
                        ModelThumbnail(model: model)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .navigationDestination(for: Model.self) { model in
                ModelView(model: model)
                    .navigationTitle(model.name)
            }
            .navigationTitle("Models")
        }
        .task {
            await viewModel.fetchModels()
        }
    }
}

#Preview {
    ModelsView()
}
