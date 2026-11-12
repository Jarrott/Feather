import AppKit
import FeatherCore
import Testing

@testable import Feather

/// 使用自有像素和隐藏窗口验证显示器事件，测试不读取屏幕、不申请权限。
@MainActor
@Suite(.serialized)
struct CaptureContinuityTests {
  @Test func screenChangeKeepsEditsButCancelsUnselectedCapture() async throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let suite = "FeatherContinuity.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let context = try #require(
      CGContext(
        data: nil, width: 800, height: 600, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let model = AppModel(defaults: defaults)
    let coordinator = CaptureCoordinator(model: model, displaysWindows: false) { _ in
      [ScreenSnapshot(screen: screen, image: image)]
    }
    var finished = false
    coordinator.onComplete = { finished = true }
    coordinator.start()
    for _ in 0..<100 where coordinator.windows.isEmpty { await Task.yield() }
    let view = try #require(coordinator.windows.first?.contentView as? SelectionView)
    view.onSelect?(CGRect(x: 40, y: 40, width: 300, height: 200))
    let document = try #require(coordinator.document)
    let annotation = Annotation(
      tool: .rectangle, points: [.zero, CGPoint(x: 50, y: 50)], color: .palette[0])
    document.add(annotation)
    let crop = document.history.cropRect
    coordinator.screenParametersChanged(screens: [])
    coordinator.screenParametersChanged(screens: [screen])
    #expect(!finished && document.history.annotations == [annotation])
    #expect(document.history.cropRect == crop && coordinator.document === document)
    #expect(coordinator.windows.first?.level == .screenSaver)
    coordinator.cancel()
    #expect(finished)
    let selecting = CaptureCoordinator(model: model, displaysWindows: false) { _ in
      [ScreenSnapshot(screen: screen, image: image)]
    }
    var cancelled = false
    selecting.onComplete = { cancelled = true }
    selecting.start()
    selecting.screenParametersChanged()
    #expect(cancelled)
  }

  @Test func fullScreenAndRepeatedRegionSelectWithoutDragging() async throws {
    _ = NSApplication.shared
    let screen = try #require(NSScreen.screens.first)
    let suite = "FeatherCaptureModes.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    let context = try #require(
      CGContext(
        data: nil, width: 800, height: 600, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    model.lastRegion = SavedRegion(
      displayID: try #require(CaptureCoordinator.displayID(screen)),
      normalizedRect: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    for mode in [CaptureMode.fullScreen, .lastRegion] {
      let coordinator = CaptureCoordinator(model: model, mode: mode, displaysWindows: false) { _ in
        [ScreenSnapshot(screen: screen, image: image)]
      }
      coordinator.start()
      for _ in 0..<100 where coordinator.document == nil { await Task.yield() }
      let document = try #require(coordinator.document)
      #expect(document.image.width == (mode == .fullScreen ? 800 : 400))
      #expect(document.image.height == (mode == .fullScreen ? 600 : 300))
      coordinator.cancel()
    }
  }
}
