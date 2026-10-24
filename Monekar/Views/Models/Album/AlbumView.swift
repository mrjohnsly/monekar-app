//
//  AlbumView.swift
//  Monekar
//
//  Created by John Sylvester on 22/10/2026.
//

import SwiftUI

struct AlbumView: View {
    
    @State private var viewModel: AlbumViewModel = AlbumViewModel()
    @State private var selectedImage: ImageItem?
    
    let album: Album
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(viewModel.images) { image in
                    Button {
                        selectedImage = image
                    } label: {
                        ThumbnailFrame(aspectRatio: image.aspectRatio) {
                            AsyncImage(url: URL(string: image.thumbnailImageURL)) { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                            } placeholder: {
                                ProgressView()
                            }
                        }
                    }
                    .buttonStyle(.plain)
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
        .overlay {
            if let selectedImage {
                GalleryView(viewModel: viewModel, selectedImageID: selectedImage.id)
            }
        }
        .background {
            HStack {
                Button("Close") {
                    selectedImage = nil
                }
                .keyboardShortcut(.cancelAction)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        }
    }
}

struct GalleryView: View {
    
    @Bindable var viewModel: AlbumViewModel
    @State var selectedImageID: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(viewModel.images) { image in
                        AsyncImage(url: URL(string: image.originalImageURL)) { loadedImage in
                            loadedImage
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ProgressView()
                                .tint(.white)
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(image.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedImageID)
            .onMoveCommand { direction in
                move(direction: direction)
            }
            .background {
                // invisible keyboard capture layer
                HStack {
                    Button("Previous") { nudge(-1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    
                    Button("Next") { nudge(1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    
                    Button("Favourite") {
                        print("Adding to favourites")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    
                    Button("Start slideshow") {
                        print("Starting slideshow...")
                    }
                    .keyboardShortcut(.return, modifiers: [])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
            }
            .onAppear {
                if let id = selectedImageID {
                    DispatchQueue.main.async {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        print("Adding to favourites...")
                    } label: {
                        Label("Favourite", systemImage: "heart")
                    }
                    
                }
            }
        }
    }
    
    private func nudge(_ delta: Int) {
        guard
            let currentID = selectedImageID,
            let index = viewModel.images.firstIndex(where: { $0.id == currentID })
                else { return }
        
        let newIndex = index + delta
        guard viewModel.images.indices.contains(newIndex) else { return }
        selectedImageID = viewModel.images[newIndex].id
    }
    
    private func move(direction: MoveCommandDirection) {
        guard
            let currentID = selectedImageID,
            let index = viewModel.images.firstIndex(where: { $0.id == currentID })
                else { return }
        
        let delta = direction == .right ? 1 : -1
        let newIndex = index + delta
        guard viewModel.images.indices.contains(newIndex) else { return }
        self.selectedImageID = viewModel.images[newIndex].id
    }
}
