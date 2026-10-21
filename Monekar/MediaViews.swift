import SwiftUI
#if os(macOS)
import AppKit
#endif

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

struct ImageViewer: View {
    let image: MonekarAPI.Image
    let services: AppServices
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

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
                    MagnifyGesture()
                        .updating($magnification) { value, state, _ in state = value.magnification }
                        .onEnded { value in zoom = min(4, max(1, zoom * value.magnification)) }
                )
            }
            .background(.black)
            .navigationTitle(image.fileName)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
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
        .onChange(of: services.api.mediaSessionID) { _, _ in dismiss() }
        #if os(macOS)
        .background(FullScreenWindow())
        #endif
    }
}

#if os(macOS)
private struct FullScreenWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { FullScreenView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class FullScreenView: NSView {
        private var requestedFullScreen = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !requestedFullScreen else { return }
            requestedFullScreen = true
            Task { @MainActor [weak window] in
                guard let window, !window.styleMask.contains(.fullScreen) else { return }
                window.toggleFullScreen(nil)
            }
        }
    }
}
#endif
