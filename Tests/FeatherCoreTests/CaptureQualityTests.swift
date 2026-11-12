import AppKit
import ImageIO
import Testing

@testable import FeatherCore

/// 高频像素与广色域输入用于发现缩放、重采样和意外颜色转换。
@MainActor
struct CaptureQualityTests {
  @Test(arguments: [false, true])
  func pngPreservesSinglePixelDetailsAndDisplayP3(withAnnotation: Bool) throws {
    let size = CGSize(width: 256, height: 128)
    let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
    var pixels = [UInt8](repeating: 255, count: Int(size.width * size.height) * 4)
    for y in 0..<Int(size.height) {
      for x in 0..<Int(size.width) {
        let offset = (y * Int(size.width) + x) * 4
        pixels[offset] = x % 2 == 0 ? 255 : 0
        pixels[offset + 1] = x % 2 == 0 ? 80 : 0
        pixels[offset + 2] = y < 64 ? 0 : 255
      }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(
      CGImage(
        width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: Int(size.width) * 4, space: space,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let crop = try #require(image.cropping(to: CGRect(x: 10, y: 4, width: 200, height: 100)))
    let annotations: [Annotation] =
      withAnnotation
      ? [
        Annotation(
          tool: .rectangle, points: [CGPoint(x: 8, y: 8), CGPoint(x: 30, y: 30)],
          color: InkColor.palette[0])
      ] : []
    let data = try AnnotationRenderer.png(image: crop, annotations: annotations)
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let decodedSpace = try #require(decoded.colorSpace)
    #expect(CFEqual(decodedSpace, space))
    #expect(decoded.width == 200 && decoded.height == 100)
    let bitmap = NSBitmapImageRep(cgImage: decoded)
    for y in [5, 75] {
      for x in 80..<100 {
        var result = [Int](repeating: 0, count: bitmap.samplesPerPixel)
        bitmap.getPixel(&result, atX: x, y: y)
        let offset = ((y + 4) * 256 + x + 10) * 4
        #expect(Array(result.prefix(3)) == pixels[offset..<(offset + 3)].map(Int.init))
      }
    }
  }
}
