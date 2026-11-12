import AppKit
import Testing

@testable import FeatherCore

struct TextAndMosaicTests {
  @Test func backgroundCoreTextRendersMultilineWithinMeasuredBounds() async throws {
    try await Task.detached {
      let context = try #require(
        CGContext(
          data: nil, width: 500, height: 240, bitsPerComponent: 8,
          bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: 500, height: 240))
      let image = try #require(context.makeImage())
      let annotation = Annotation(
        tool: .text, points: [CGPoint(x: 30, y: 20)], color: InkColor(0, 0, 0),
        text: "中文 ABC\nSecond 行", fontSize: 34)
      let data = try AnnotationRenderer.png(image: image, annotations: [annotation])
      let bitmap = try #require(NSBitmapImageRep(data: data))
      let bounds = AnnotationGeometry.bounds(of: annotation)
      var first = 0
      var second = 0
      for y in 0..<240 {
        for x in 0..<500 {
          let pixel = try #require(bitmap.colorAt(x: x, y: y))
          if pixel.redComponent < 0.5 {
            #expect(bounds.insetBy(dx: -1, dy: -1).contains(CGPoint(x: x, y: y)))
            if CGFloat(y) < bounds.midY { first += 1 } else { second += 1 }
          }
        }
      }
      #expect(first > 10 && second > 10)
    }.value
  }

  @Test func mosaicDoesNotRevealSolidRedaction() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 80, height: 80, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 80, height: 80))
    let image = try #require(context.makeImage())
    let black = Annotation(
      tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)], color: .palette[0])
    let mosaic = Annotation(
      tool: .mosaic, points: [.zero, CGPoint(x: 60, y: 60)], color: .palette[0])
    for annotations in [[black, mosaic], [mosaic, black]] {
      let bitmap = try #require(
        NSBitmapImageRep(data: AnnotationRenderer.png(image: image, annotations: annotations)))
      #expect(bitmap.colorAt(x: 20, y: 20)?.redComponent == 0)
      #expect(bitmap.colorAt(x: 70, y: 70)?.redComponent == 1)
    }
  }
}
