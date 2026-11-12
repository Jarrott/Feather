import AppKit
import Testing

@testable import FeatherCore

/// 非对称测试图片可同时检测像素尺寸、上下倒置和标注坐标偏差。
@MainActor
struct RenderingTests {
  private func sourceImage() throws -> CGImage {
    let width = 100
    let height = 80
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        pixels[offset] = y < height / 2 ? 255 : 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = y < height / 2 ? 0 : 255
      }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    return try #require(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  }

  @Test func compositeMatchesEncodedPNGAndSkipsCopyWithoutAnnotations() throws {
    let image = try sourceImage()
    #expect(try AnnotationRenderer.composite(image: image, annotations: []) === image)
    let annotations = [
      Annotation(
        tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)],
        color: InkColor.palette[0])
    ]
    let composed = try AnnotationRenderer.composite(image: image, annotations: annotations)
    let data = try AnnotationRenderer.png(image: image, annotations: annotations)
    let decoded = try #require(NSBitmapImageRep(data: data))
    let direct = NSBitmapImageRep(cgImage: composed)
    #expect(direct.pixelsWide == decoded.pixelsWide && direct.pixelsHigh == decoded.pixelsHigh)
    for point in [(20, 15), (50, 10), (50, 70)] {
      #expect(direct.colorAt(x: point.0, y: point.1) == decoded.colorAt(x: point.0, y: point.1))
    }
    #expect(direct.colorAt(x: 20, y: 15)?.redComponent == 0)
  }

  @Test func losslessExportPreservesSizeAndOrientation() throws {
    let data = try AnnotationRenderer.png(image: sourceImage(), annotations: [])
    let result = try #require(NSBitmapImageRep(data: data))
    #expect(result.pixelsWide == 100 && result.pixelsHigh == 80)
    // 比较文件解码后的原始通道，避免 NSColor 的 ICC 转换舍入影响无损验证。
    var top = [Int](repeating: 0, count: result.samplesPerPixel)
    var bottom = top
    result.getPixel(&top, atX: 50, y: 5)
    result.getPixel(&bottom, atX: 50, y: 75)
    #expect(Array(top.prefix(3)) == [255, 0, 0])
    #expect(Array(bottom.prefix(3)) == [0, 0, 255])
  }

  @Test func cropUsesTopLeftCoordinates() throws {
    let image = try sourceImage()
    let crop = try #require(image.cropping(to: CGRect(x: 10, y: 5, width: 20, height: 10)))
    let result = NSBitmapImageRep(cgImage: crop)
    #expect(result.pixelsWide == 20 && result.pixelsHigh == 10)
    let pixel = try #require(result.colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB))
    #expect(pixel.redComponent > 0.99)
  }

  @Test func redactionReplacesPixelsAtExpectedCoordinates() throws {
    let annotation = Annotation(
      tool: .redact, points: [CGPoint(x: 10, y: 5), CGPoint(x: 30, y: 20)],
      color: InkColor.palette[0])
    let data = try AnnotationRenderer.png(image: sourceImage(), annotations: [annotation])
    let result = try #require(NSBitmapImageRep(data: data))
    let pixel = try #require(result.colorAt(x: 15, y: 10)?.usingColorSpace(.sRGB))
    #expect(pixel.redComponent == 0 && pixel.greenComponent == 0 && pixel.blueComponent == 0)
    #expect(pixel.alphaComponent == 1)
    let outside = try #require(result.colorAt(x: 15, y: 60)?.usingColorSpace(.sRGB))
    #expect(outside.blueComponent > 0.99)
  }

  @Test func everyToolRendersVisiblePixels() throws {
    let image = try sourceImage()
    let original = try AnnotationRenderer.png(image: image, annotations: [])
    for tool in AnnotationTool.allCases {
      let annotation = Annotation(
        tool: tool, points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: tool == .mosaic ? 60 : 30)],
        color: InkColor(0, 1, 0), lineWidth: 3, text: "Test 标注")
      let result = try AnnotationRenderer.png(image: image, annotations: [annotation])
      #expect(result != original, "Tool \(tool.rawValue) should change visible pixels")
    }
  }

  @Test func highlightRetainsUnderlyingImage() throws {
    let annotation = Annotation(
      tool: .highlight, points: [CGPoint(x: 10, y: 5), CGPoint(x: 30, y: 20)],
      color: InkColor(0, 1, 0))
    let data = try AnnotationRenderer.png(image: sourceImage(), annotations: [annotation])
    let result = try #require(NSBitmapImageRep(data: data))
    let pixel = try #require(result.colorAt(x: 15, y: 10)?.usingColorSpace(.sRGB))
    #expect(pixel.redComponent > 0.5 && pixel.greenComponent > 0.1 && pixel.alphaComponent == 1)
  }

  @Test func exportCreatesUniqueFilesWithoutOverwriting() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let data = try AnnotationRenderer.png(image: sourceImage(), annotations: [])
    let now = Date(timeIntervalSince1970: 0)
    let first = try PNGExporter.save(data, to: directory, now: now)
    let second = try PNGExporter.save(data, to: directory, now: now)
    #expect(first != second)
    #expect(try Data(contentsOf: first) == data)
    #expect(try Data(contentsOf: second) == data)
  }

  @Test func invalidDataAndDirectoryAreRejected() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(throws: ExportError.self) { try PNGExporter.save(Data("not png".utf8), to: directory) }
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    try Data("file".utf8).write(to: directory)
    let png = try AnnotationRenderer.png(image: sourceImage(), annotations: [])
    #expect(throws: ExportError.self) { try PNGExporter.save(png, to: directory) }
  }
}
