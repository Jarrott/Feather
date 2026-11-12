import AppKit
import Testing

@testable import Feather

/// 只渲染自有像素图，检查预览的原生比例与上下方向，不调用屏幕截图。
@MainActor
struct CapturePreviewTests {
  @Test func nativePixelPreviewKeepsEdgesSharpAndUpright() throws {
    _ = NSApplication.shared
    let frame = CGRect(x: 0, y: 0, width: 256, height: 128)
    let window = NSWindow(
      contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let width = Int(frame.width * window.backingScaleFactor)
    let height = Int(frame.height * window.backingScaleFactor)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        let offset = (y * width + x) * 4
        pixels[offset] = y < height / 2 && x % 2 == 0 ? 255 : 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = y >= height / 2 && x % 2 == 0 ? 255 : 0
      }
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(
      CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let view = SelectionView(image: image, frame: frame)
    window.contentView = view
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide == width && bitmap.pixelsHigh == height)
    for x in 80..<90 {
      let top = try #require(bitmap.colorAt(x: x, y: 10)?.usingColorSpace(.sRGB))
      let bottom = try #require(bitmap.colorAt(x: x, y: height - 10)?.usingColorSpace(.sRGB))
      // 框选前有 27% 遮罩；原生像素仍必须保持清晰的明暗交替，不能混合相邻像素。
      if x % 2 == 0 {
        // 预览经过本机显示器 ICC 转换，以主色通道检查方向；PNG 原值由核心测试精确验证。
        #expect(top.redComponent > 0.5 && top.redComponent > top.blueComponent * 3)
        #expect(bottom.blueComponent > 0.5 && bottom.blueComponent > bottom.redComponent * 3)
      } else {
        #expect(top.redComponent < 0.01 && top.greenComponent < 0.01 && top.blueComponent < 0.01)
        #expect(
          bottom.redComponent < 0.01 && bottom.greenComponent < 0.01 && bottom.blueComponent < 0.01)
      }
    }
  }
}
