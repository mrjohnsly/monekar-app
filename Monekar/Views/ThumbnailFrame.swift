import SwiftUI

struct ThumbnailFrame<Content: View>: View {
    var aspectRatio: CGFloat = 1
    @ViewBuilder var content: Content

    var body: some View {
        // The image loading phase must not change the grid row's height.
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay { content }
            .clipped()
    }
}
