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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 4)], spacing: 4) {
                    ForEach(viewModel.models) { model in
                        NavigationLink(value: model) {
                            ModelThumbnail(model: model)
                        }
                        .buttonStyle(.plain)
                        .task {
                            if model.id == viewModel.models.last?.id {
                                await viewModel.fetchModels()
                            }
                        }
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
            if viewModel.models.isEmpty {
                await viewModel.fetchModels()
            }
        }
    }
}
