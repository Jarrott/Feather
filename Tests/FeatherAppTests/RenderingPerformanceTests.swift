import AppKit
import FeatherCore
import Testing

@testable import Feather

/// 按需执行 6K 基准；只渲染生成图，不读取屏幕。结果用于同机比较，不设易波动的绝对耗时门槛。
@MainActor
struct RenderingPerformanceTests {
  @Test(.enabled(if: ProcessInfo.processInfo.environment["FEATHER_RUN_BENCHMARKS"] == "1"))
  func sixKExportAndDirtyRegionBenchmark() async throws {
    _ = NSApplication.shared
    let width = 6144
    let height = 3456
    let image = try await Task.detached {
      var pixels = [UInt32](repeating: 0, count: width * height)
      for i in pixels.indices {
        pixels[i] = 0xFF00_0000 | (UInt32(truncatingIfNeeded: i) &* 2_654_435_761 & 0x00FF_FFFF)
      }
      let data = pixels.withUnsafeBytes { Data($0) }
      let provider = try #require(CGDataProvider(data: data as CFData))
      return try #require(
        CGImage(
          width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
          bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
          provider: provider,
          decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }.value
    let annotations = (0..<20).map { i in
      Annotation(
        tool: i % 2 == 0 ? .text : .rectangle,
        points: [CGPoint(x: 50 + i * 100, y: 100), CGPoint(x: 150 + i * 100, y: 220)],
        color: .palette[i % 6], text: "Feather 测试 \(i)", fontSize: 42)
    }
    let clock = ContinuousClock()
    let encodeStart = clock.now
    let bytes = try await Task.detached {
      return try AnnotationRenderer.png(image: image, annotations: annotations).count
    }.value
    let encode = encodeStart.duration(to: clock.now)
    let suite = "FeatherBenchmark.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let view = SelectionView(image: image, frame: CGRect(x: 0, y: 0, width: width, height: height))
    let document = EditorDocument(image: image, appModel: AppModel(defaults: defaults))
    for annotation in annotations { document.add(annotation) }
    view.beginEditing(document, pixelRect: view.bounds)
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    let frames = 30
    let fullStart = clock.now
    for _ in 0..<frames {
      context.draw(image, in: view.bounds)
      view.drawOverlay(view.bounds)
    }
    let full = fullStart.duration(to: clock.now)
    let partialStart = clock.now
    for _ in 0..<frames { view.drawOverlay(CGRect(x: 40, y: 40, width: 256, height: 256)) }
    let partial = partialStart.duration(to: clock.now)
    print(
      "FEATHER_BENCHMARK pixels=\(width)x\(height) png_bytes=\(bytes) encode=\(encode) frames=\(frames) full_redraw=\(full) dirty_overlay=\(partial)"
    )
    #expect(bytes > 0)
  }
}
