#if canImport(ImageIO)
import Foundation
import CoreGraphics
import ImageIO
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

struct MediaImageDecoderTests {
    @Test func largeImageIsDownsampledToDisplayBudget() async throws {
        let context = try #require(CGContext(
            data: nil, width: 4096, height: 2048, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let decoded = try await MediaImageDecoder.decode(data as Data, maxPixelSize: 512)
        #expect(decoded.image.width == 512)
        #expect(decoded.image.height == 256)
    }

    @Test func corruptImagesFailAndCancellationIsPreserved() async {
        await #expect(throws: ConnectionFailure.invalidResponse) {
            try await MediaImageDecoder.decode(Data([1, 2, 3]), maxPixelSize: 512)
        }
        let task = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await MediaImageDecoder.decode(Data(), maxPixelSize: 512)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}
#endif
