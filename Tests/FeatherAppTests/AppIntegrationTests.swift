import AppKit
import FeatherCore
import SwiftUI
import Testing

@testable import Feather

/// 使用隔离偏好和临时目录测试应用，不读取屏幕、不修改系统权限或用户剪贴板。
@MainActor
@Suite(.serialized)
struct AppIntegrationTests {
  private func withModel(_ body: (AppModel) async throws -> Void) async throws {
    let suite = "FeatherTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(AppModel(defaults: defaults))
  }

  @Test func preferencesSurviveModelRecreation() throws {
    let suite = "FeatherPersistenceTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = AppModel(defaults: defaults)
    first.copyAfterSave = false
    first.showCursor = true
    first.saveDirectory = URL(fileURLWithPath: "/tmp/FeatherExports", isDirectory: true)
    first.registerShortcut(.controlOptionS, using: { _ in })
    let restored = AppModel(defaults: defaults)
    #expect(!restored.copyAfterSave && restored.showCursor)
    #expect(restored.shortcut == .controlOptionS)
    #expect(restored.saveDirectory == first.saveDirectory)
    #expect(!restored.shortcutActive)
  }

  @Test func editorSavesAnnotatedPNG() async throws {
    try await withModel { model in
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      model.saveDirectory = directory
      model.copyAfterSave = false
      let document = EditorDocument(image: try fixture(), appModel: model)
      document.add(
        Annotation(
          tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
          color: InkColor.palette[0]))
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      document.save(closeAfter: true)
      // 保存 API 同步锁定状态，后台任务完成后才解除锁定。
      #expect(document.isExporting)
      for _ in 0..<200 where document.isExporting { try await Task.sleep(for: .milliseconds(10)) }
      #expect(!document.isExporting)
      #expect(document.error == nil)
      #expect(closeCount == 1)
      let url = try #require(document.savedURL)
      #expect(FileManager.default.fileExists(atPath: url.path))
      let image = try #require(NSBitmapImageRep(data: Data(contentsOf: url)))
      #expect(image.pixelsWide == 640 && image.pixelsHigh == 400)
      #expect(image.colorAt(x: 20, y: 20)?.redComponent == 0)
    }
  }

  @Test func failedSavePreservesAnnotationsAndCanRetry() async throws {
    try await withModel { model in
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let invalid = root.appendingPathComponent("not-a-directory")
      try Data("fixture".utf8).write(to: invalid)
      model.saveDirectory = invalid
      model.copyAfterSave = false
      let document = EditorDocument(image: try fixture(), appModel: model)
      document.add(
        Annotation(
          tool: .arrow, points: [.zero, CGPoint(x: 40, y: 40)], color: InkColor.palette[0]))
      let annotations = document.history.annotations
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      document.save(closeAfter: true)
      for _ in 0..<200 where document.isExporting { try await Task.sleep(for: .milliseconds(10)) }
      #expect(document.error != nil)
      #expect(document.savedURL == nil)
      #expect(document.history.annotations == annotations)
      #expect(closeCount == 0)
      model.saveDirectory = root.appendingPathComponent("valid")
      document.save(closeAfter: true)
      for _ in 0..<200 where document.isExporting { try await Task.sleep(for: .milliseconds(10)) }
      #expect(document.error == nil)
      #expect(document.savedURL != nil)
      #expect(closeCount == 1)
    }
  }

  @Test func toolToggleReturnsToSelectionWithoutChangingAnnotations() async throws {
    try await withModel { model in
      let document = EditorDocument(image: try fixture(), appModel: model)
      document.add(
        Annotation(
          tool: .rectangle, points: [.zero, CGPoint(x: 40, y: 40)], color: InkColor.palette[0]))
      let annotations = document.history.annotations
      document.selectTool(.rectangle, toggleSelection: true)
      #expect(document.tool == .rectangle && !document.isSelectingRegion)
      document.selectTool(.rectangle, toggleSelection: true)
      #expect(document.isSelectingRegion)
      document.selectTool(.rectangle)
      document.selectTool(.rectangle)
      #expect(!document.isSelectingRegion)
      document.selectTool(.text, toggleSelection: true)
      #expect(document.tool == .text && !document.isSelectingRegion)
      document.isExporting = true
      document.selectTool(.pen, toggleSelection: true)
      #expect(document.tool == .text && !document.isSelectingRegion)
      #expect(document.history.annotations == annotations)
    }
  }

  @Test func nativeViewsRenderOffscreen() async throws {
    _ = NSApplication.shared
    try await withModel { model in
      let directory = ProcessInfo.processInfo.environment["FEATHER_PREVIEW_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
      }
      if let directory {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      }
      try await render(
        NSHostingView(rootView: PreferencesView(model: model)),
        size: CGSize(width: 560, height: 600), to: directory?.appendingPathComponent("settings.png")
      )
      let source = try fixture()
      let pixels = CGRect(x: 60, y: 30, width: 420, height: 240)
      let cropped = try #require(source.cropping(to: pixels))
      let document = EditorDocument(image: cropped, appModel: model)
      document.add(
        Annotation(
          tool: .arrow, points: [CGPoint(x: 80, y: 170), CGPoint(x: 260, y: 75)],
          color: InkColor.palette[0], lineWidth: 4))
      document.add(
        Annotation(
          tool: .text, points: [CGPoint(x: 100, y: 185)], color: InkColor(0.1, 0.3, 0.3),
          lineWidth: 4, text: "Feather · 轻截"))
      document.isSelectingRegion = false
      let overlay = SelectionView(
        image: source, frame: CGRect(x: 0, y: 0, width: 1024, height: 640))
      overlay.beginEditing(document, pixelRect: pixels)
      try await render(
        overlay, size: CGSize(width: 1024, height: 640),
        to: directory?.appendingPathComponent("overlay.png"))
      document.isSelectingRegion = true
      try await render(
        overlay, size: CGSize(width: 1024, height: 640),
        to: directory?.appendingPathComponent("selection.png"))
      if let directory {
        try AnnotationRenderer.png(image: document.image, annotations: document.history.annotations)
          .write(to: directory.appendingPathComponent("annotated-export.png"))
      }
      // 覆盖底边、全屏和窄屏浮层布局；输入始终来自测试图，不读取用户屏幕。
      for (name, size, rect, tool) in [
        (
          "bottom-edge", CGSize(width: 1024, height: 640),
          CGRect(x: 400, y: 330, width: 220, height: 60), AnnotationTool.text
        ),
        (
          "fullscreen", CGSize(width: 1024, height: 640),
          CGRect(x: 0, y: 0, width: 640, height: 400), .redact
        ),
        (
          "narrow", CGSize(width: 600, height: 500), CGRect(x: 60, y: 30, width: 420, height: 240),
          .highlight
        ),
      ] {
        let crop = try #require(source.cropping(to: rect))
        let editor = EditorDocument(image: crop, appModel: model)
        editor.selectTool(tool)
        let view = SelectionView(image: source, frame: CGRect(origin: .zero, size: size))
        view.beginEditing(editor, pixelRect: rect)
        try await render(view, size: size, to: directory?.appendingPathComponent(name + ".png"))
        if name == "bottom-edge" {
          editor.error = L.text("copy.failed")
          try await render(
            view, size: size, to: directory?.appendingPathComponent("export-error.png"))
        }
      }
    }
  }

  /// 只渲染应用自有视图，不将窗口显示到屏幕，测试产物仅按显式环境变量写入。
  private func render(_ view: NSView, size: CGSize, to url: URL?) async throws {
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    view.setFrameSize(size)
    view.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(60))
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide >= Int(size.width))
    #expect(bitmap.pixelsHigh >= Int(size.height))
    if let url {
      let data = try #require(bitmap.representation(using: .png, properties: [:]))
      try data.write(to: url)
    }
    window.close()
  }

  private func fixture() throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: 640, height: 400, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 0.94, green: 0.97, blue: 0.95, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
    context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.45, alpha: 1))
    context.fill(CGRect(x: 60, y: 230, width: 200, height: 35))
    context.setFillColor(CGColor(red: 0.7, green: 0.8, blue: 0.75, alpha: 1))
    context.fill(CGRect(x: 60, y: 170, width: 490, height: 12))
    return try #require(context.makeImage())
  }
}
