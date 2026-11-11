import AppKit
import FeatherCore
import Testing

@testable import Feather

/// 直接向未显示的测试视图传入事件对象，不注入系统输入、不读取桌面内容。
@MainActor
@Suite(.serialized)
struct OverlayInteractionTests {
  @Test func selectionStaysInPlaceAndSupportsMoveResizeAndAnnotations() throws {
    _ = NSApplication.shared
    let suite = "FeatherOverlayTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let model = AppModel(defaults: defaults)
    let context = try #require(
      CGContext(
        data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = SelectionView(image: image, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    defer { view.onSelect = nil }
    window.contentView = view
    var selectedRect: CGRect?
    var document: EditorDocument?
    view.onSelect = { rect in
      selectedRect = rect
      guard let cropped = image.cropping(to: rect) else { return }
      let editor = EditorDocument(image: cropped, appModel: model)
      document = editor
      view.beginEditing(editor, pixelRect: rect)
    }
    try drag(view, window: window, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 400, y: 300))
    #expect(selectedRect == CGRect(x: 100, y: 100, width: 300, height: 200))
    let editor = try #require(document)
    editor.add(
      Annotation(
        tool: .arrow, points: [CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 80)],
        color: InkColor.palette[0]))
    try drag(view, window: window, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 220, y: 230))
    #expect(editor.image.width == 300 && editor.image.height == 200)
    #expect(editor.history.annotations[0].points[0] == CGPoint(x: 30, y: 20))
    try drag(view, window: window, from: CGPoint(x: 420, y: 330), to: CGPoint(x: 465, y: 355))
    #expect(editor.image.width == 345 && editor.image.height == 225)
    editor.isSelectingRegion = false
    editor.tool = .rectangle
    try drag(view, window: window, from: CGPoint(x: 150, y: 160), to: CGPoint(x: 225, y: 220))
    #expect(editor.history.annotations.count == 2)
    #expect(editor.history.annotations.last?.rect == CGRect(x: 30, y: 30, width: 75, height: 60))
    let undo = try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "z", charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6))
    #expect(view.performKeyEquivalent(with: undo))
    #expect(editor.history.annotations.count == 1)
    var cancelled = false
    view.onCancel = { cancelled = true }
    view.rightMouseDown(with: try mouse(.rightMouseDown, point: .zero, window: window))
    #expect(cancelled)
  }

  @Test func doubleClickCopiesAnnotatedSelectionAndClosesOnce() throws {
    try withSelection { view, document, window, pasteboard in
      document.add(
        Annotation(
          tool: .redact, points: [CGPoint(x: 10, y: 10), CGPoint(x: 40, y: 40)],
          color: InkColor.palette[0]))
      let annotations = document.history.annotations
      var closeCount = 0
      document.onClose = {
        #expect(pasteboard.data(forType: .png) != nil)
        closeCount += 1
      }
      try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 1)
      #expect(closeCount == 0 && pasteboard.data(forType: .png) == nil)
      try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 2)
      #expect(closeCount == 1 && document.error == nil)
      #expect(document.history.annotations == annotations)
      #expect(document.savedURL == nil)
      let data = try #require(pasteboard.data(forType: .png))
      let image = try #require(NSBitmapImageRep(data: data))
      #expect(image.pixelsWide == 300 && image.pixelsHigh == 200)
      #expect(image.colorAt(x: 20, y: 20)?.redComponent == 0)
      #expect((image.colorAt(x: 60, y: 60)?.redComponent ?? 0) > 0.9)
    }
  }

  @Test func doubleClickOutsideOnHandlesWhileDrawingOrExportingDoesNotConfirm() throws {
    try withSelection { view, document, window, pasteboard in
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      try click(view, window: window, at: CGPoint(x: 500, y: 200), count: 2)
      try click(view, window: window, at: CGPoint(x: 102, y: 102), count: 2)
      document.isExporting = true
      try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 2)
      document.isExporting = false
      for tool in [AnnotationTool.rectangle, .pen] {
        document.selectTool(tool)
        try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 1)
        try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 2)
      }
      #expect(closeCount == 0 && pasteboard.data(forType: .png) == nil)
      #expect(document.history.annotations.count == 2)
      #expect(document.history.annotations.allSatisfy { $0.tool == .pen })
    }
  }

  /// 构造未显示的选区与独立剪贴板，结束后释放资源；不访问桌面、系统剪贴板或真实用户偏好。
  private func withSelection(
    _ body: (SelectionView, EditorDocument, NSWindow, NSPasteboard) throws -> Void
  ) throws {
    _ = NSApplication.shared
    let suite = "FeatherDoubleClickTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let context = try #require(
      CGContext(
        data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
    let image = try #require(context.makeImage())
    let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
    let document = EditorDocument(
      image: try #require(image.cropping(to: rect)), appModel: AppModel(defaults: defaults),
      pasteboard: pasteboard)
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = SelectionView(image: image, frame: window.contentLayoutRect)
    window.contentView = view
    view.beginEditing(document, pixelRect: rect)
    try body(view, document, window, pasteboard)
  }

  private func click(_ view: SelectionView, window: NSWindow, at point: CGPoint, count: Int) throws
  {
    view.mouseDown(with: try mouse(.leftMouseDown, point: point, window: window, clickCount: count))
    view.mouseUp(with: try mouse(.leftMouseUp, point: point, window: window, clickCount: count))
  }

  private func drag(_ view: SelectionView, window: NSWindow, from start: CGPoint, to end: CGPoint)
    throws
  {
    view.mouseDown(with: try mouse(.leftMouseDown, point: start, window: window))
    view.mouseDragged(with: try mouse(.leftMouseDragged, point: end, window: window))
    view.mouseUp(with: try mouse(.leftMouseUp, point: end, window: window))
  }

  private func mouse(
    _ type: NSEvent.EventType, point: CGPoint, window: NSWindow, clickCount: Int = 1
  ) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type, location: CGPoint(x: point.x, y: 600 - point.y), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: clickCount, pressure: 1))
  }
}
