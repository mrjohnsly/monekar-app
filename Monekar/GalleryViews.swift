import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private let galleryColumns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 16)]

struct PeopleView: View {
    let coordinator: AppCoordinator

    private var viewModel: PaginatedViewModel<MonekarAPI.Person> { coordinator.people }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("People")
                    .font(.largeTitle.bold())
                LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
                    ForEach(viewModel.items) { person in
                        VStack(alignment: .leading, spacing: 6) {
                            GalleryThumbnail(
                                reference: person.thumbnailURL,
                                services: coordinator.services,
                                open: { coordinator.showPerson(id: person.id) }
                            )
                            Button {
                                coordinator.showPerson(id: person.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(person.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(person.albumCount) albums · \(person.imageCount) images")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("person-\(person.id)")
                        }
                    }
                }
                if viewModel.items.isEmpty && viewModel.state == .empty {
                    GalleryEmptyView(title: "No people", description: "No people are available on this server.")
                }
                GalleryFooter(
                    count: viewModel.items.count, total: viewModel.total,
                    isLoading: viewModel.isLoading || viewModel.state == .idle,
                    hasError: viewModel.hasError, hasMore: viewModel.hasMore,
                    retry: { await viewModel.retry() },
                    loadMore: { await viewModel.loadMore() }
                )
            }
            .padding()
        }
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.refresh() }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh() }
            }
            .disabled(viewModel.isLoading)
            .accessibilityIdentifier("refreshPeople")
        }
    }
}

struct PersonDetailView: View {
    let viewModel: PersonViewModel
    let coordinator: AppCoordinator

    var body: some View {
        @Bindable var viewModel = viewModel
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.detail.state {
                case .idle, .loading:
                    ProgressView("Loading person…")
                case .loaded(let person):
                    VStack(alignment: .leading, spacing: 6) {
                        Text(person.name).font(.largeTitle.bold())
                        Text("\(person.albumCount) albums · \(person.imageCount) images")
                            .foregroundStyle(.secondary)
                    }
                case .empty:
                    GalleryEmptyView(title: "Person not found", description: "This person is no longer available.")
                case .failed:
                    GalleryRetryView(message: "Unable to load this person.") {
                        await viewModel.detail.refresh()
                    }
                }
                if viewModel.detail.hasError && !isDetailFailed {
                    GalleryRetryView(message: "Unable to refresh person details.") {
                        await viewModel.detail.refresh()
                    }
                }
                Picker("Show", selection: $viewModel.selection) {
                    Text("Albums").tag(PersonSection.albums)
                    Text("Images").tag(PersonSection.images)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("personSection")

                switch viewModel.selection {
                case .albums:
                    AlbumGrid(viewModel: viewModel.albums, coordinator: coordinator)
                case .images:
                    ImageGrid(viewModel: viewModel.images, services: coordinator.services)
                }
            }
            .padding()
        }
        .navigationTitle("Person")
        .task { await viewModel.detail.loadIfNeeded() }
        .task { await loadSelectedSection(viewModel.selection) }
        .onChange(of: viewModel.selection) { _, selection in
            Task {
                await loadSelectedSection(selection)
            }
        }
        .refreshable { await refresh() }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(viewModel.detail.isLoading || viewModel.albums.isLoading || viewModel.images.isLoading)
        }
    }

    private var isDetailFailed: Bool {
        if case .failed = viewModel.detail.state { return true }
        return false
    }

    private func loadSelectedSection(_ section: PersonSection) async {
        switch section {
        case .albums: await viewModel.albums.loadIfNeeded()
        case .images: await viewModel.images.loadIfNeeded()
        }
    }

    private func refresh() async {
        await viewModel.detail.refresh()
        switch viewModel.selection {
        case .albums: await viewModel.albums.refresh()
        case .images: await viewModel.images.refresh()
        }
    }
}

struct AlbumDetailView: View {
    let viewModel: AlbumViewModel
    let services: AppServices

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch viewModel.detail.state {
                case .idle, .loading:
                    ProgressView("Loading album…")
                case .loaded(let album):
                    VStack(alignment: .leading, spacing: 8) {
                        Text(album.name).font(.largeTitle.bold())
                        Text("\(album.imageCount) images").foregroundStyle(.secondary)
                        if let date = album.date, !date.isEmpty {
                            Label(date, systemImage: "calendar")
                        }
                        if let models = album.models, !models.isEmpty {
                            Text("Models: \(models)")
                        }
                        if let photographer = album.photographer, !photographer.isEmpty {
                            Text("Photographer: \(photographer)")
                        }
                    }
                case .empty:
                    GalleryEmptyView(title: "Album not found", description: "This album is no longer available.")
                case .failed:
                    GalleryRetryView(message: "Unable to load this album.") {
                        await viewModel.detail.refresh()
                    }
                }
                if viewModel.detail.hasError && !isDetailFailed {
                    GalleryRetryView(message: "Unable to refresh album details.") {
                        await viewModel.detail.refresh()
                    }
                }
                ImageGrid(viewModel: viewModel.images, services: services)
            }
            .padding()
        }
        .navigationTitle("Album")
        .task {
            await viewModel.detail.loadIfNeeded()
            await viewModel.images.loadIfNeeded()
        }
        .refreshable { await refresh() }
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await refresh() }
            }
            .disabled(viewModel.detail.isLoading || viewModel.images.isLoading)
        }
    }

    private var isDetailFailed: Bool {
        if case .failed = viewModel.detail.state { return true }
        return false
    }

    private func refresh() async {
        await viewModel.detail.refresh()
        await viewModel.images.refresh()
    }
}

private struct AlbumGrid: View {
    let viewModel: PaginatedViewModel<MonekarAPI.Album>
    let coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
                ForEach(viewModel.items) { album in
                    VStack(alignment: .leading, spacing: 6) {
                        GalleryThumbnail(
                            reference: album.thumbnailURL,
                            services: coordinator.services,
                            open: { coordinator.showAlbum(id: album.id) }
                        )
                        Button {
                            coordinator.showAlbum(id: album.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(album.name).font(.headline).foregroundStyle(.primary)
                                Text("\(album.imageCount) images").font(.caption).foregroundStyle(.secondary)
                                if let date = album.date, !date.isEmpty {
                                    Text(date).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("album-\(album.id)")
                    }
                }
            }
            if viewModel.items.isEmpty && viewModel.state == .empty {
                GalleryEmptyView(title: "No albums", description: "No albums are available for this person.")
            }
            GalleryFooter(
                count: viewModel.items.count, total: viewModel.total,
                isLoading: viewModel.isLoading || viewModel.state == .idle,
                hasError: viewModel.hasError, hasMore: viewModel.hasMore,
                retry: { await viewModel.retry() },
                loadMore: { await viewModel.loadMore() }
            )
        }
    }
}

private struct ImageGrid: View {
    let viewModel: PaginatedViewModel<MonekarAPI.Image>
    let services: AppServices

    var body: some View {
        VStack(spacing: 16) {
            LazyVGrid(columns: galleryColumns, alignment: .leading, spacing: 20) {
                ForEach(viewModel.items) { image in
                    VStack(alignment: .leading, spacing: 6) {
                        GalleryThumbnail(reference: image.thumbnailURL, services: services)
                        Text(image.fileName).font(.headline).lineLimit(2)
                        Text("\(image.format) · \(ByteCountFormatter.string(fromByteCount: image.byteSize, countStyle: .file))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let width = image.width, let height = image.height {
                            Text("\(width) × \(height)").font(.caption).foregroundStyle(.secondary)
                        }
                        if image.isFavourite {
                            Label("Favourite", systemImage: "heart.fill").font(.caption)
                        }
                        if !image.tags.isEmpty {
                            Text(image.tags.map(\.name).joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("image-\(image.id)")
                }
            }
            if viewModel.items.isEmpty && viewModel.state == .empty {
                GalleryEmptyView(title: "No images", description: "No images are available here.")
            }
            GalleryFooter(
                count: viewModel.items.count, total: viewModel.total,
                isLoading: viewModel.isLoading || viewModel.state == .idle,
                hasError: viewModel.hasError, hasMore: viewModel.hasMore,
                retry: { await viewModel.retry() },
                loadMore: { await viewModel.loadMore() }
            )
        }
    }
}

private struct GalleryFooter: View {
    let count: Int
    let total: Int
    let isLoading: Bool
    let hasError: Bool
    let hasMore: Bool
    let retry: () async -> Void
    let loadMore: () async -> Void

    var body: some View {
        VStack(spacing: 12) {
            if count > 0 {
                Text("\(count) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isLoading {
                ProgressView(count == 0 ? "Loading…" : "Loading more…")
            } else if hasError {
                GalleryRetryView(message: "Unable to load data. Check your connection and try again.", retry: retry)
            } else if hasMore {
                Button("Load more") {
                    Task { await loadMore() }
                }
                .accessibilityIdentifier("loadMore")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

private struct GalleryRetryView: View {
    let message: String
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await retry() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct GalleryEmptyView: View {
    let title: String
    let description: String

    var body: some View {
        ContentUnavailableView(title, systemImage: "photo.on.rectangle", description: Text(description))
            .frame(maxWidth: .infinity)
    }
}

private struct GalleryThumbnail: View {
    let reference: String
    let services: AppServices
    var open: (() -> Void)?
    @State private var image: SwiftUI.Image?
    @State private var isLoading = true
    @State private var hasFailed = false
    @State private var attempt = 0

    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if hasFailed {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                        Button("Retry thumbnail") { attempt += 1 }
                            .buttonStyle(.bordered)
                    }
                } else if let open {
                    Button(action: open) {
                        thumbnailContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open details")
                } else {
                    thumbnailContent
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .accessibilityLabel("Thumbnail")
            .task(id: "\(attempt):\(reference)") { await load() }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image {
            image.resizable().scaledToFill()
        } else if isLoading {
            ProgressView()
        } else {
            Image(systemName: "photo")
        }
    }

    private func load() async {
        image = nil
        hasFailed = false
        isLoading = true
        do {
            let data = try await services.api.get(mediaReference: reference)
            try Task.checkCancellation()
            #if canImport(UIKit)
            if let decoded = UIImage(data: data) {
                image = SwiftUI.Image(uiImage: decoded)
            }
            #elseif canImport(AppKit)
            if let decoded = NSImage(data: data) {
                image = SwiftUI.Image(nsImage: decoded)
            }
            #endif
            hasFailed = image == nil
            isLoading = false
        } catch is CancellationError {
            isLoading = false
        } catch {
            hasFailed = true
            isLoading = false
        }
    }
}
