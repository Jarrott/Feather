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

  @Test func doubleClickCopiesAnnotatedSelectionAndClosesOnce() async throws {
    try await withSelection { view, document, window, pasteboard in
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

  @Test func doubleClickOutsideOnHandlesOrExportingDoesNotConfirm() async throws {
    try await withSelection { view, document, window, pasteboard in
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      try click(view, window: window, at: CGPoint(x: 500, y: 200), count: 2)
      try click(view, window: window, at: CGPoint(x: 102, y: 102), count: 2)
      document.isExporting = true
      try click(view, window: window, at: CGPoint(x: 200, y: 200), count: 2)
      #expect(closeCount == 0 && pasteboard.data(forType: .png) == nil)
      #expect(document.history.annotations.isEmpty)
    }
  }

  @Test(arguments: AnnotationTool.allCases)
  func everyToolCanDoubleClickToFinishWithoutExtraMarks(tool: AnnotationTool) async throws {
    var textRequests = 0
    let requestText: @MainActor () -> String? = {
      textRequests += 1
      return "unexpected"
    }
    try await withSelection(requestText: requestText) { view, document, window, pasteboard in
      document.add(
        Annotation(
          tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 70)],
          color: InkColor.palette[0]))
      // 保留一个重做分支，验证画笔双击撤回首击时不会丢失此前的历史。
      document.add(
        Annotation(
          tool: .arrow, points: [.zero, CGPoint(x: 20, y: 20)], color: InkColor.palette[0]))
      document.history.undo()
      let annotations = document.history.annotations
      document.selectTool(tool)
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      // 等待此前的 Published 通知，模拟用户选工具后再点击。
      await Task.yield()
      try click(view, window: window, at: CGPoint(x: 300, y: 250), count: 1)
      try click(view, window: window, at: CGPoint(x: 300, y: 250), count: 2)
      try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.05))
      #expect(closeCount == 1 && textRequests == 0)
      #expect(document.history.annotations == annotations && document.history.canRedo)
      let data = try #require(pasteboard.data(forType: .png))
      let bitmap = try #require(NSBitmapImageRep(data: data))
      #expect((bitmap.colorAt(x: 200, y: 150)?.redComponent ?? 0) > 0.9)
      #expect((bitmap.colorAt(x: 200, y: 150)?.greenComponent ?? 0) > 0.9)
    }
  }

  @Test(arguments: AnnotationTool.allCases)
  func doubleClickWithSmallPointerJitterDiscardsFirstMark(tool: AnnotationTool) async throws {
    try await withSelection { view, document, window, pasteboard in
      document.selectTool(tool)
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      view.mouseDown(
        with: try mouse(.leftMouseDown, point: CGPoint(x: 300, y: 250), window: window))
      view.mouseUp(with: try mouse(.leftMouseUp, point: CGPoint(x: 302, y: 251), window: window))
      try click(view, window: window, at: CGPoint(x: 302, y: 251), count: 2)
      #expect(closeCount == 1 && document.history.annotations.isEmpty)
      #expect(pasteboard.data(forType: .png) != nil)
    }
  }

  @Test(arguments: [CGFloat(1), CGFloat(2)])
  func drawnRectangleCanMoveUndoAndExportAtOriginalResolution(scale: CGFloat) async throws {
    try await withSelection(scale: scale) { view, document, window, pasteboard in
      document.selectTool(.rectangle)
      func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x / scale, y: y / scale) }
      try drag(view, window: window, from: point(140, 140), to: point(240, 220))
      let original = try #require(document.history.annotations.first)
      try drag(view, window: window, from: point(140, 180), to: point(190, 200))
      #expect(document.history.annotations.count == 1)
      let moved = try #require(document.history.annotations.first)
      #expect(moved.id == original.id && moved.rect == CGRect(x: 90, y: 60, width: 100, height: 80))
      #expect(document.image.width == 300 && document.image.height == 200)
      try await preview(view, name: "moved-annotation-\(Int(scale))x.png")
      document.history.undo()
      #expect(document.history.annotations == [original])
      document.history.redo()
      #expect(document.history.annotations == [moved])
      try click(view, window: window, at: point(300, 260), count: 1)
      try click(view, window: window, at: point(300, 260), count: 2)
      let data = try #require(pasteboard.data(forType: .png))
      let bitmap = try #require(NSBitmapImageRep(data: data))
      #expect(bitmap.pixelsWide == 300 && bitmap.pixelsHigh == 200)
      #expect((bitmap.colorAt(x: 90, y: 90)?.greenComponent ?? 1) < 0.5)
      #expect((bitmap.colorAt(x: 40, y: 70)?.greenComponent ?? 0) > 0.9)
    }
  }

  @Test func topmostAnnotationMovesAndEmptyRectangleInteriorStillDraws() async throws {
    try await withSelection { view, document, window, _ in
      document.selectTool(.rectangle)
      let first = Annotation(
        tool: .rectangle, points: [CGPoint(x: 20, y: 20), CGPoint(x: 180, y: 140)],
        color: InkColor.palette[0])
      let second = Annotation(tool: .rectangle, points: first.points, color: InkColor.palette[1])
      document.add(first)
      document.add(second)
      try drag(view, window: window, from: CGPoint(x: 120, y: 180), to: CGPoint(x: 140, y: 190))
      #expect(document.history.annotations[0] == first)
      #expect(document.history.annotations[1].points[0] == CGPoint(x: 40, y: 30))
      try drag(view, window: window, from: CGPoint(x: 180, y: 170), to: CGPoint(x: 220, y: 200))
      #expect(document.history.annotations.count == 3)
      try drag(
        view, window: window, from: CGPoint(x: 120, y: 160), to: CGPoint(x: 160, y: 200),
        modifiers: .option)
      #expect(document.history.annotations.count == 4)
      #expect(document.history.annotations[0] == first)
    }
  }

  @Test func singleTextClickStillRequestsTextAndWindowCloseCancelsDeferredInput() async throws {
    var requests = 0
    let requestText: @MainActor () -> String? = {
      requests += 1
      return "Note"
    }
    try await withSelection(requestText: requestText) { view, document, window, _ in
      document.selectTool(.text)
      await Task.yield()
      try click(view, window: window, at: CGPoint(x: 300, y: 250), count: 1)
      try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
      #expect(requests == 1 && document.history.annotations.first?.text == "Note")
      try click(view, window: window, at: CGPoint(x: 180, y: 180), count: 1)
      window.contentView = nil
      try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
      #expect(requests == 1)
    }
  }

  @Test func deleteKeyRemovesSelectedAnnotationAndUndoRestoresIt() async throws {
    try await withSelection { view, document, window, _ in
      document.selectTool(.rectangle)
      try drag(view, window: window, from: CGPoint(x: 140, y: 140), to: CGPoint(x: 240, y: 220))
      try drag(view, window: window, from: CGPoint(x: 260, y: 150), to: CGPoint(x: 330, y: 230))
      let annotations = document.history.annotations
      #expect(annotations.count == 2)
      // 未选中时按 Delete 不改变标注；点中第一个矩形边线后删除它。
      try click(view, window: window, at: CGPoint(x: 360, y: 280), count: 1)
      view.keyDown(with: try key(51, window: window))
      #expect(document.history.annotations == annotations)
      try click(view, window: window, at: CGPoint(x: 140, y: 180), count: 1)
      view.keyDown(with: try key(51, window: window))
      #expect(document.history.annotations == [annotations[1]])
      view.keyDown(with: try key(51, window: window))
      #expect(document.history.annotations == [annotations[1]])
      document.history.undo()
      #expect(document.history.annotations == annotations)
    }
  }

  @Test func keypadEnterCopiesAndCloses() async throws {
    try await withSelection { view, document, window, pasteboard in
      var closeCount = 0
      document.onClose = { closeCount += 1 }
      view.keyDown(with: try key(76, window: window, characters: "\u{3}"))
      #expect(closeCount == 1 && pasteboard.data(forType: .png) != nil)
    }
  }

  private func key(_ code: UInt16, window: NSWindow, characters: String = "\u{7F}") throws
    -> NSEvent
  {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
  }

  /// 构造未显示的选区与独立剪贴板，结束后释放资源；不访问桌面、系统剪贴板或真实用户偏好。
  private func withSelection(
    scale: CGFloat = 1, requestText: @escaping @MainActor () -> String? = { nil },
    _ body: @MainActor (SelectionView, EditorDocument, NSWindow, NSPasteboard) async throws -> Void
  ) async throws {
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
      contentRect: CGRect(x: 0, y: 0, width: 800 / scale, height: 600 / scale),
      styleMask: .borderless,
      backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let view = SelectionView(
      image: image, frame: window.contentLayoutRect, requestText: requestText)
    window.contentView = view
    view.beginEditing(document, pixelRect: rect)
    try await body(view, document, window, pasteboard)
  }

  private func click(_ view: SelectionView, window: NSWindow, at point: CGPoint, count: Int) throws
  {
    view.mouseDown(with: try mouse(.leftMouseDown, point: point, window: window, clickCount: count))
    view.mouseUp(with: try mouse(.leftMouseUp, point: point, window: window, clickCount: count))
  }

  private func drag(
    _ view: SelectionView, window: NSWindow, from start: CGPoint, to end: CGPoint,
    modifiers: NSEvent.ModifierFlags = []
  ) throws {
    view.mouseDown(
      with: try mouse(.leftMouseDown, point: start, window: window, modifiers: modifiers))
    view.mouseDragged(with: try mouse(.leftMouseDragged, point: end, window: window))
    view.mouseUp(with: try mouse(.leftMouseUp, point: end, window: window))
  }

  private func mouse(
    _ type: NSEvent.EventType, point: CGPoint, window: NSWindow, clickCount: Int = 1,
    modifiers: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try #require(
      NSEvent.mouseEvent(
        with: type,
        location: CGPoint(x: point.x, y: (window.contentView?.bounds.height ?? 600) - point.y),
        modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 1, clickCount: clickCount, pressure: 1))
  }

  /// 仅在显式指定目录时保存自有视图的离屏预览；不显示窗口、不读取用户桌面。
  private func preview(_ view: NSView, name: String) async throws {
    guard let path = ProcessInfo.processInfo.environment["FEATHER_PREVIEW_DIR"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try await Task.sleep(for: .milliseconds(60))
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    try data.write(to: directory.appendingPathComponent(name))
  }
}
