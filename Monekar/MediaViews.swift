import SwiftUI

struct AuthenticatedImageView: View {
    let reference: String
    let loader: MediaLoader
    let label: String
    var thumbnailSize: MonekarAPI.ThumbnailSize?
    var maxPixelSize = 2048
    @State private var image: DecodedMediaImage?
    @State private var isPlaceholder = false
    @State private var isLoading = true
    @State private var hasFailed = false
    @State private var attempt = 0

    private struct LoadID: Hashable {
        let reference: String
        let size: Int?
        let pixels: Int
        let attempt: Int
        let connection: UUID?
    }

    var body: some View {
        Group {
            if hasFailed {
                VStack(spacing: 8) {
                    Label("Unable to load image", systemImage: "exclamationmark.triangle")
                    Button("Retry image", systemImage: "arrow.clockwise") { attempt += 1 }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Retry image: \(label)")
                }
                .font(.caption)
                .padding(8)
            } else if let image {
                Image(image.image, scale: 1, label: Text(label))
                    .resizable()
                    .aspectRatio(contentMode: thumbnailSize == nil ? .fit : .fill)
                    .accessibilityLabel(label)
                    .accessibilityAddTraits(.isImage)
            } else if isPlaceholder {
                Label("No cover image", systemImage: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No cover image: \(label)")
            } else if isLoading {
                ProgressView("Loading image…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: LoadID(
            reference: reference, size: thumbnailSize?.rawValue, pixels: maxPixelSize,
            attempt: attempt, connection: loader.connectionID
        )) {
            await load()
        }
    }

    private func load() async {
        image = nil
        hasFailed = false
        isPlaceholder = false
        isLoading = true
        do {
            let resource = try await loader.load(reference: reference, size: thumbnailSize, reload: attempt > 0)
            if resource.isPlaceholder {
                try Task.checkCancellation()
                isPlaceholder = true
            } else {
                let decoded = try await MediaImageDecoder.decode(resource.data, maxPixelSize: maxPixelSize)
                try Task.checkCancellation()
                image = decoded
            }
            isLoading = false
        } catch is CancellationError {
            // A disappearing or replaced view must not overwrite the next load's state.
        } catch {
            guard !Task.isCancelled else { return }
            hasFailed = true
            isLoading = false
        }
    }
}

struct ImageViewerSelection: Identifiable {
    let images: [MonekarAPI.Image]
    let selectedImageID: Int

    var id: Int { selectedImageID }
}

struct ImageViewer: View {
    let selection: ImageViewerSelection
    let services: AppServices
    let onDismiss: () -> Void
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1
    @State private var selectedIndex: Int
    @FocusState private var isFocused: Bool

    init(selection: ImageViewerSelection, services: AppServices, onDismiss: @escaping () -> Void) {
        self.selection = selection
        self.services = services
        self.onDismiss = onDismiss
        _selectedIndex = State(
            initialValue: selection.images.firstIndex { $0.id == selection.selectedImageID } ?? 0
        )
    }

    private var image: MonekarAPI.Image { selection.images[selectedIndex] }

    private var effectiveZoom: CGFloat { min(4, max(1, zoom * magnification)) }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    AuthenticatedImageView(
                        reference: image.originalURL, loader: services.media, label: image.fileName,
                        maxPixelSize: 4096
                    )
                    .frame(
                        width: geometry.size.width * effectiveZoom,
                        height: geometry.size.height * effectiveZoom
                    )
                }
                .defaultScrollAnchor(.center)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            guard zoom <= 1,
                                  abs(value.translation.width) > 50,
                                  abs(value.translation.width) > abs(value.translation.height)
                            else { return }
                            if value.translation.width < 0 {
                                showNextImage()
                            } else {
                                showPreviousImage()
                            }
                        }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(4, max(1, zoom * value.magnification)) }
                )
            }
            .background(.black)
            .safeAreaInset(edge: .bottom) {
                ImageManagementControls(viewModel: services.imageLibrary.model(for: image))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .navigationTitle(image.fileName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark", action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("closeImageViewer")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom - 1) }
                        .disabled(zoom <= 1)
                    Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(4, zoom + 1) }
                        .disabled(zoom >= 4)
                    Button("Fit image", systemImage: "arrow.down.right.and.arrow.up.left") { zoom = 1 }
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("imageViewer")
        .onChange(of: services.api.mediaSessionID) { _, _ in onDismiss() }
        .focusable()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.leftArrow) { _ in
            showPreviousImage()
            return .handled
        }
        .onKeyPress(.rightArrow) { _ in
            showNextImage()
            return .handled
        }
        .onChange(of: selectedIndex) { _, _ in zoom = 1 }
    }

    private func showPreviousImage() {
        guard selectedIndex > 0 else { return }
        selectedIndex -= 1
    }

    private func showNextImage() {
        guard selectedIndex < selection.images.count - 1 else { return }
        selectedIndex += 1
    }
}

struct ImageManagementControls: View {
    let viewModel: ImageViewModel
    @State private var showsTags = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(
                    viewModel.image.isFavourite ? "Unfavourite" : "Favourite",
                    systemImage: viewModel.image.isFavourite ? "heart.fill" : "heart"
                ) {
                    Task { await viewModel.setFavourite(!viewModel.image.isFavourite) }
                }
                .disabled(viewModel.isBusy)
                .accessibilityIdentifier("favourite-\(viewModel.image.id)")
                Button("Tags", systemImage: "tag") { showsTags = true }
                    .accessibilityIdentifier("tags-\(viewModel.image.id)")
            }
            .buttonStyle(.bordered)
            if let message = viewModel.errorMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .sheet(isPresented: $showsTags) {
            ImageTagsView(viewModel: viewModel)
        }
    }
}

private struct ImageTagsView: View {
    @Bindable var viewModel: ImageViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Image tags") {
                    if viewModel.image.tags.isEmpty {
                        Text("No tags").foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.image.tags) { tag in
                        HStack {
                            Text(tag.name)
                            Spacer()
                            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                                Task { await viewModel.removeTag(id: tag.id) }
                            }
                            .accessibilityLabel("Remove tag: \(tag.name)")
                            .disabled(viewModel.isBusy)
                        }
                    }
                }
                Section("Add tag") {
                    TextField("Tag name", text: $viewModel.tagName)
                        .onSubmit { Task { await viewModel.addTag() } }
                        .accessibilityIdentifier("tagName")
                    Button("Add tag") { Task { await viewModel.addTag() } }
                        .disabled(viewModel.isBusy)
                }
                if viewModel.isBusy { ProgressView("Updating image…") }
                if let message = viewModel.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
            }
            .navigationTitle("Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Reload tags", systemImage: "arrow.clockwise") {
                        Task { await viewModel.loadTags() }
                    }
                    .disabled(viewModel.isBusy)
                }
            }
            .task { await viewModel.loadTags() }
        }
        .frame(minWidth: 280, minHeight: 320)
    }
}
