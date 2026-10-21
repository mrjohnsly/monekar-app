#if canImport(ImageIO)
import Foundation
import ImageIO

nonisolated struct DecodedMediaImage: @unchecked Sendable {
    let image: CGImage
}

nonisolated enum MediaImageDecoder {
    static func decode(_ data: Data, maxPixelSize: Int) async throws -> DecodedMediaImage {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary
            ), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(4096, max(1, maxPixelSize)),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary) else {
                throw ConnectionFailure.invalidResponse
            }
            try Task.checkCancellation()
            return DecodedMediaImage(image: image)
        }
        return try await withTaskCancellationHandler {
            let image = try await task.value
            try Task.checkCancellation()
            return image
        } onCancel: {
            task.cancel()
        }
    }
}
#endif
