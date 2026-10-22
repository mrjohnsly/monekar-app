#if canImport(SwiftUI) && !SWIFT_PACKAGE
import SwiftUI
import Testing
@testable import Monekar

@MainActor
struct ThumbnailFrameTests {
    @Test(arguments: [CGFloat(150), 250, 320])
    func loadingLoadedAndFailedContentKeepTheSameSize(width: CGFloat) throws {
        for ratio: CGFloat in [0.5, 1, 2] {
            let loading = try renderedSize(width: width, ratio: ratio) {
                ProgressView()
            }
            let loaded = try renderedSize(width: width, ratio: ratio) {
                Image(systemName: "photo")
                    .resizable()
                    .scaledToFit()
            }
            let failed = try renderedSize(width: width, ratio: ratio) {
                Image(systemName: "exclamationmark.triangle")
            }
            #expect(loading == CGSize(width: width, height: width / ratio))
            #expect(loaded == loading)
            #expect(failed == loading)
        }
    }

    @Test func oversizedContentCannotExpandTheThumbnail() throws {
        let size = try renderedSize(width: 250, ratio: 1) {
            Color.red.frame(width: 1000, height: 1000)
        }
        #expect(size == CGSize(width: 250, height: 250))
    }

    private func renderedSize<Content: View>(
        width: CGFloat, ratio: CGFloat, @ViewBuilder content: () -> Content
    ) throws -> CGSize {
        let renderer = ImageRenderer(content:
            ThumbnailFrame(aspectRatio: ratio, content: content)
                .frame(width: width)
        )
        let image = try #require(renderer.cgImage)
        return CGSize(width: image.width, height: image.height)
    }
}
#endif
