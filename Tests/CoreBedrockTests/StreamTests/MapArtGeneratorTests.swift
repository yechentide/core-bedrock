@testable import CoreBedrock
import CoreGraphics
import Foundation
import Testing

struct MapArtGeneratorTests {
    @Test func tileRenderingPreservesFullBitmapOrderingAndPadding() throws {
        let width = 129
        let height = 131
        var source = [UInt8]()
        for y in 0..<height {
            for x in 0..<width {
                source.append(contentsOf: [UInt8(x), UInt8(y), 31, 255])
            }
        }
        let image = try #require(source.withUnsafeMutableBytes { buffer in
            CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        })
        var fullBitmap = [UInt8](repeating: 0, count: width * height * 4)
        try fullBitmap.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        for tileY in 0..<2 {
            for tileX in 0..<2 {
                let actual = try MapArtGenerator.tileBytes(image: image, x: tileX, y: tileY)
                var expected = [UInt8](repeating: 0, count: 128 * 128 * 4)
                for y in 0..<128 where tileY * 128 + y < height {
                    for x in 0..<128 where tileX * 128 + x < width {
                        let index = ((tileY * 128 + y) * width + tileX * 128 + x) * 4
                        expected.replaceSubrange((y * 128 + x) * 4..<(y * 128 + x) * 4 + 4,
                                                 with: fullBitmap[index..<index + 4])
                    }
                }
                #expect(actual.elementsEqual(expected))
            }
        }
    }
}
