import Foundation
import Testing

@testable import FeatherCore

struct GeometryTests {
  @Test func reverseDragIsNormalizedAndClipped() {
    let result = CaptureGeometry.selection(
      from: CGPoint(x: 120, y: 80), to: CGPoint(x: -20, y: 10),
      bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
    #expect(result == CGRect(x: 0, y: 10, width: 100, height: 70))
  }

  @Test func retinaSelectionPreservesPixels() {
    let result = CaptureGeometry.pixelRect(
      selection: CGRect(x: 10, y: 20, width: 200, height: 100),
      viewSize: CGSize(width: 800, height: 600),
      imageSize: CGSize(width: 1600, height: 1200))
    #expect(result == CGRect(x: 20, y: 40, width: 400, height: 200))
  }

  @Test func fractionalPixelsRoundOutAndStayWithinImage() {
    let result = CaptureGeometry.pixelRect(
      selection: CGRect(x: 90.2, y: 90.1, width: 20, height: 30),
      viewSize: CGSize(width: 100, height: 100),
      imageSize: CGSize(width: 150, height: 200))
    #expect(result == CGRect(x: 135, y: 180, width: 15, height: 20))
  }

  @Test func negativeDisplayOriginDoesNotAffectLocalCoordinates() {
    // 每屏窗口先转成局部坐标；左侧显示器不应把全局负坐标带入像素裁剪。
    let displayOrigin = CGPoint(x: -1920, y: 200)
    let global = CGPoint(x: -1820, y: 250)
    let local = CGPoint(x: global.x - displayOrigin.x, y: global.y - displayOrigin.y)
    let result = CaptureGeometry.pixelRect(
      selection: CGRect(origin: local, size: CGSize(width: 300, height: 150)),
      viewSize: CGSize(width: 1920, height: 1080),
      imageSize: CGSize(width: 1920, height: 1080))
    #expect(result == CGRect(x: 100, y: 50, width: 300, height: 150))
  }

  @Test func invalidSelectionsAreRejected() {
    let size = CGSize(width: 100, height: 100)
    for rect in [
      CGRect.zero, CGRect(x: 2, y: 2, width: 1, height: 50),
      CGRect(x: 200, y: 200, width: 10, height: 10),
      CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20),
    ] {
      #expect(CaptureGeometry.pixelRect(selection: rect, viewSize: size, imageSize: size) == nil)
    }
    #expect(
      CaptureGeometry.pixelRect(
        selection: CGRect(x: 0, y: 0, width: 50, height: 50),
        viewSize: .zero, imageSize: size) == nil)
  }

  @Test func fittingUsesLetterboxingWithoutDistortion() {
    #expect(
      CaptureGeometry.fit(
        image: CGSize(width: 400, height: 200),
        inside: CGRect(x: 10, y: 10, width: 200, height: 200))
        == CGRect(x: 10, y: 60, width: 200, height: 100))
  }
}
