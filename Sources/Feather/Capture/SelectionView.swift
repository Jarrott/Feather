import AppKit
import Combine
import FeatherCore
import SwiftUI

/// 单屏冻结画面、可调选区与就地标注；屏幕局部逻辑点和原图像素之间只在此转换。
@MainActor
final class SelectionView: NSView {
  var onSelect: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?
  private let source: CGImage
  private var selection = CGRect.zero
  private var pixelRect = CGRect.zero
  private var document: EditorDocument?
  private var toolbar: NSHostingView<CaptureToolbar>?
  private var toolOptions: NSHostingView<CaptureToolOptions>?
  private var observation: AnyCancellable?
  private var start: CGPoint?
  private var originalRect = CGRect.zero
  private var pending: Annotation?
  private var selectedAnnotationID: UUID?
  private var clickMark: (id: UUID, history: AnnotationHistory)?
  private var textClickTask: Task<Void, Never>?
  private let requestText: @MainActor () -> String?
  private var drag: Drag?
  private enum Drag {
    case selecting, moving
    case resizing(SelectionHandle)
    case drawing, text
    case movingAnnotation(Annotation)
  }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  /// 创建冻结画面；文字输入默认使用原生面板，测试可注入输入器，不改变系统截图权限。
  init(
    image: CGImage, frame: CGRect,
    requestText: @escaping @MainActor () -> String? = SelectionView.promptForText
  ) {
    source = image
    self.requestText = requestText
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) { nil }

  /// 将框选结果切换为同一屏幕上的编辑状态；工具条不进入截图，观察者随视图释放。
  func beginEditing(_ document: EditorDocument, pixelRect: CGRect) {
    self.document = document
    self.pixelRect = pixelRect
    selection = logicalRect(pixelRect)
    let toolbar = NSHostingView(
      rootView: CaptureToolbar(document: document, onCancel: { [weak self] in self?.onCancel?() }))
    self.toolbar = toolbar
    addSubview(toolbar)
    let options = NSHostingView(rootView: CaptureToolOptions(document: document))
    toolOptions = options
    addSubview(options)
    observation = document.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in
        self?.cancelTextClick()
        self?.refresh()
      }
    }
    refresh()
  }

  /// 根据当前选区和导出状态重排两个浮层；属性尽量朝选区外侧展开，不改变原图或标注。
  private func refresh() {
    needsDisplay = true
    if let document {
      if !document.history.annotations.contains(where: { $0.id == selectedAnnotationID }) {
        selectedAnnotationID = nil
      }
      let frame = SelectionGeometry.toolbarFrame(
        selection: selection,
        size: CaptureToolbar.preferredSize, bounds: bounds)
      toolbar?.frame = frame
      if let size = CaptureToolOptions.preferredSize(for: document) {
        toolOptions?.isHidden = false
        toolOptions?.frame = SelectionGeometry.optionsFrame(
          toolbar: frame, size: size, bounds: bounds, preferAbove: frame.maxY <= selection.minY)
      } else {
        toolOptions?.isHidden = true
      }
    }
    window?.invalidateCursorRects(for: self)
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
    if let document {
      addCursorRect(
        selection,
        cursor: document.isSelectingRegion
          ? .openHand : (document.tool == .text ? .iBeam : .crosshair))
      for handle in SelectionHandle.allCases {
        let point = handle.point(in: selection)
        let cursor: NSCursor =
          [.top, .bottom].contains(handle)
          ? .resizeUpDown : [.left, .right].contains(handle) ? .resizeLeftRight : .crosshair
        addCursorRect(CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12), cursor: cursor)
      }
    }
    for control in [toolbar as NSView?, toolOptions as NSView?].compactMap({ $0 })
    where !control.isHidden {
      addCursorRect(control.frame, cursor: .arrow)
    }
  }

  /// 在冻结画面上绘制编辑预览；移动替换原层中的标注，辅助框仅在此显示，不进入 PNG。
  override func draw(_ dirtyRect: NSRect) {
    // 直接绘制原始 CGImage，避免 NSImage 的中间表示和插值使细字、单像素线变软。
    if let context = NSGraphicsContext.current?.cgContext {
      context.saveGState()
      context.interpolationQuality = .none
      context.translateBy(x: 0, y: bounds.height)
      context.scaleBy(x: 1, y: -1)
      context.draw(source, in: bounds)
      context.restoreGState()
    }
    let shade = NSBezierPath(rect: bounds)
    if !selection.isEmpty { shade.appendRect(selection) }
    shade.windingRule = .evenOdd
    NSColor.black.withAlphaComponent(0.27).setFill()
    shade.fill()
    if let document, let context = NSGraphicsContext.current?.cgContext {
      context.saveGState()
      context.clip(to: selection)
      context.translateBy(x: selection.minX, y: selection.minY)
      context.scaleBy(
        x: bounds.width / CGFloat(source.width), y: bounds.height / CGFloat(source.height))
      for annotation in document.history.annotations {
        if let pending, pending.id == annotation.id {
          AnnotationRenderer.draw(pending, in: context)
        } else {
          AnnotationRenderer.draw(annotation, in: context)
        }
      }
      if let pending, !document.history.annotations.contains(where: { $0.id == pending.id }) {
        AnnotationRenderer.draw(pending, in: context)
      }
      if let selected = pending
        ?? document.history.annotations.first(where: { $0.id == selectedAnnotationID })
      {
        let scale = CGFloat(source.width) / bounds.width
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        context.setShadow(offset: .zero, blur: 2 * scale, color: NSColor.black.cgColor)
        context.setLineWidth(scale)
        context.setLineDash(phase: 0, lengths: [3 * scale, 3 * scale])
        context.stroke(
          AnnotationGeometry.bounds(of: selected).insetBy(dx: -4 * scale, dy: -4 * scale))
      }
      context.restoreGState()
    }
    if !selection.isEmpty {
      let green = CaptureStyle.selectionColor
      green.setStroke()
      let border = NSBezierPath(rect: selection)
      border.lineWidth = 1
      border.stroke()
      green.setFill()
      for handle in SelectionHandle.allCases {
        let point = handle.point(in: selection)
        let size: CGFloat =
          [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle) ? 6 : 5
        NSBezierPath(
          rect: CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        ).fill()
      }
      if let pixels = cropRect(selection) {
        drawDimensions("\(Int(pixels.width)) × \(Int(pixels.height))")
      }
    }
    if document == nil, selection.isEmpty {
      drawInstruction()
    }
  }

  /// 双击选区确认优先于标注操作，所有工具一致；单击命中标注可移动，绿框手柄继续缩放。
  /// 导出中忽略输入；确认前撤回双击首击生成的小标记，文字单击延后至双击间隔结束。
  override func mouseDown(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    cancelTextClick()
    window?.makeKey()
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    start = point
    originalRect = selection
    pending = nil
    drag = nil
    guard let document else {
      selection = .zero
      drag = .selecting
      needsDisplay = true
      return
    }
    let handle = SelectionHandle.allCases.first { handle in
      let position = handle.point(in: selection)
      return hypot(position.x - point.x, position.y - point.y) <= 8
    }
    if handle == nil, selection.contains(point), event.clickCount == 2 {
      if let clickMark, document.history.annotations.last?.id == clickMark.id {
        document.history = clickMark.history
      }
      clickMark = nil
      start = nil
      document.copy(closeAfter: true)
      refresh()
      return
    }
    clickMark = nil
    if let handle {
      drag = .resizing(handle)
    } else if selection.contains(point) {
      let pixel = imagePoint(point)
      let tolerance =
        6 * max(CGFloat(source.width) / bounds.width, CGFloat(source.height) / bounds.height)
      // 按绘制顺序从上向下命中；Option 可在已有标注上继续画新标注。
      if !event.modifierFlags.contains(.option),
        let annotation = document.history.annotations.last(where: {
          AnnotationGeometry.contains(pixel, in: $0, tolerance: tolerance)
        })
      {
        selectedAnnotationID = annotation.id
        drag = .movingAnnotation(annotation)
      } else {
        selectedAnnotationID = nil
        if document.isSelectingRegion {
          drag = .moving
        } else if document.tool == .text {
          drag = .text
        } else {
          drag = .drawing
          pending = Annotation(
            tool: document.tool, points: [pixel], color: document.color,
            lineWidth: document.lineWidth)
        }
      }
    } else {
      selectedAnnotationID = nil
    }
    needsDisplay = true
  }

  /// 将鼠标位移转换为原图像素并预览；标注移动限于图片边界，抬起前不写入撤销历史。
  override func mouseDragged(with event: NSEvent) {
    guard let start, let drag, document?.isExporting != true else { return }
    let point = convert(event.locationInWindow, from: nil)
    let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
    switch drag {
    case .selecting: selection = CaptureGeometry.selection(from: start, to: point, bounds: bounds)
    case .moving: changeSelection(SelectionGeometry.move(originalRect, by: delta, inside: bounds))
    case .resizing(let handle):
      changeSelection(
        SelectionGeometry.resize(originalRect, handle: handle, by: delta, inside: bounds))
    case .text: break
    case .movingAnnotation(let annotation):
      let offset = AnnotationGeometry.constrainedOffset(
        CGPoint(
          x: delta.x * CGFloat(source.width) / bounds.width,
          y: delta.y * CGFloat(source.height) / bounds.height),
        for: annotation, inside: CGRect(origin: .zero, size: pixelRect.size))
      pending = annotation.translated(by: offset)
    case .drawing:
      guard var pending else { return }
      let pixel = imagePoint(point)
      if pending.tool == .pen {
        if let last = pending.points.last, hypot(last.x - pixel.x, last.y - pixel.y) < 1 { return }
        if pending.points.count < 20_000 { pending.points.append(pixel) }
      } else {
        pending.points = [pending.points[0], pixel]
      }
      self.pending = pending
    }
    refresh()
  }

  /// 抬起时只提交一次拖动历史；短距离单击暂存原历史，便于双击确认撤回首击抖动造成的标记。
  override func mouseUp(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    mouseDragged(with: event)
    if case .movingAnnotation(let original) = drag, let pending,
      let first = original.points.first, let moved = pending.points.first
    {
      document?.moveAnnotation(
        id: original.id, by: CGPoint(x: moved.x - first.x, y: moved.y - first.y))
    } else if case .text = drag, let start {
      let point = convert(event.locationInWindow, from: nil)
      if hypot(point.x - start.x, point.y - start.y) < 3 { scheduleText(at: imagePoint(start)) }
    } else if let pending, let document {
      let visible =
        pending.tool == .pen
        || (pending.tool == .arrow
          ? pending.rect.width > 2 || pending.rect.height > 2
          : pending.rect.width > 2 && pending.rect.height > 2)
      if visible {
        let history = document.history
        document.add(pending)
        if document.history.annotations.last?.id == pending.id {
          selectedAnnotationID = pending.id
          if let start, event.clickCount == 1 {
            let end = convert(event.locationInWindow, from: nil)
            if hypot(end.x - start.x, end.y - start.y) < 3 {
              clickMark = (pending.id, history)
            }
          }
        }
      }
    }
    pending = nil
    start = nil
    drag = nil
    if document == nil, selection.width >= 4, selection.height >= 4 { onSelect?(selection) }
    refresh()
  }

  override func keyDown(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    cancelTextClick()
    clickMark = nil
    if event.keyCode == 53 {
      onCancel?()
      return
    }
    guard let document else {
      super.keyDown(with: event)
      return
    }
    if event.keyCode == 36 {
      document.copy(closeAfter: true)
    } else if let key = event.charactersIgnoringModifiers?.lowercased() {
      if key == "v" || key == "0" {
        document.isSelectingRegion = true
      } else if let index = Int(key), (1...7).contains(index) {
        document.selectTool(AnnotationTool.allCases[index - 1])
      } else {
        super.keyDown(with: event)
      }
    }
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard let document, event.modifierFlags.contains(.command), !document.isExporting else {
      return super.performKeyEquivalent(with: event)
    }
    cancelTextClick()
    clickMark = nil
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "s": document.save(asNewLocation: event.modifierFlags.contains(.shift), closeAfter: true)
    case "c": document.copy(closeAfter: true)
    case "z":
      if event.modifierFlags.contains(.shift) {
        document.history.redo()
      } else {
        document.history.undo()
      }
    default: return super.performKeyEquivalent(with: event)
    }
    refresh()
    return true
  }

  override func rightMouseDown(with event: NSEvent) {
    if document?.isExporting != true {
      cancelTextClick()
      onCancel?()
    }
  }

  /// 对新的逻辑选区进行像素对齐与裁剪，保留标注的原屏幕位置以及撤销历史。
  private func changeSelection(_ rect: CGRect) {
    guard let document, let pixels = cropRect(rect), pixels != pixelRect,
      let image = source.cropping(to: pixels)
    else { return }
    document.updateCrop(
      image,
      annotationOffset: CGPoint(x: pixelRect.minX - pixels.minX, y: pixelRect.minY - pixels.minY))
    pixelRect = pixels
    selection = logicalRect(pixels)
  }

  private func cropRect(_ selection: CGRect) -> CGRect? {
    CaptureGeometry.pixelRect(
      selection: selection, viewSize: bounds.size,
      imageSize: CGSize(width: source.width, height: source.height))
  }

  private func logicalRect(_ pixels: CGRect) -> CGRect {
    let x = bounds.width / CGFloat(source.width)
    let y = bounds.height / CGFloat(source.height)
    return CGRect(
      x: pixels.minX * x, y: pixels.minY * y, width: pixels.width * x, height: pixels.height * y)
  }

  private func imagePoint(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: min(
        pixelRect.width, max(0, (point.x - selection.minX) * CGFloat(source.width) / bounds.width)),
      y: min(
        pixelRect.height,
        max(0, (point.y - selection.minY) * CGFloat(source.height) / bounds.height)))
  }

  /// 文字首击等待系统双击间隔，第二击、工具变化、输出或窗口释放均取消；不进行后台轮询。
  private func scheduleText(at point: CGPoint) {
    textClickTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
      guard !Task.isCancelled, let self, self.window != nil,
        let document = self.document, !document.isExporting,
        !document.isSelectingRegion, document.tool == .text
      else { return }
      self.textClickTask = nil
      self.insertText(at: point)
    }
  }

  private func cancelTextClick() {
    textClickTask?.cancel()
    textClickTask = nil
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { cancelTextClick() }
    super.viewWillMove(toWindow: newWindow)
  }

  /// 调用文字输入器并提交非空文本；输入取消不修改历史，结束后恢复覆盖层键盘焦点。
  private func insertText(at point: CGPoint) {
    guard let document, let value = requestText() else { return }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    let annotation = Annotation(
      tool: .text, points: [point], color: document.color, lineWidth: document.lineWidth, text: text
    )
    document.add(annotation)
    selectedAnnotationID = annotation.id
    window?.makeFirstResponder(self)
  }

  /// 原生文字面板支持中文输入法与粘贴；返回用户确认的文字，取消返回 nil，不访问截图数据。
  private static func promptForText() -> String? {
    let alert = NSAlert()
    alert.window.level = .modalPanel
    alert.messageText = L.text("editor.textTitle")
    alert.addButton(withTitle: L.text("editor.textAdd"))
    alert.addButton(withTitle: L.text("cancel"))
    let field = NSTextField(frame: CGRect(x: 0, y: 0, width: 340, height: 28))
    field.placeholderString = L.text("editor.textPlaceholder")
    alert.accessoryView = field
    alert.window.initialFirstResponder = field
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    return field.stringValue
  }

  /// 尺寸文字贴近选区左上边缘，使用阴影保持明暗背景可读；顶边无空间时放在选区内。
  private func drawDimensions(_ text: String) {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = CGSize(width: 0, height: -1)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
      .foregroundColor: NSColor.white, .shadow: shadow,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    let x = max(6, min(selection.minX + 2, bounds.maxX - size.width - 6))
    let y =
      selection.minY >= size.height + 7 ? selection.minY - size.height - 5 : selection.minY + 8
    (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
  }

  /// 尚未框选时在底部显示简短操作说明，开始拖选后隐藏；尺寸按本地化文字计算并居中。
  private func drawInstruction() {
    let text = L.text("capture.instruction")
    let attributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .regular),
      .foregroundColor: NSColor.white,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    let origin = CGPoint(
      x: max(8, bounds.midX - (size.width + 24) / 2), y: bounds.maxY - size.height - 52)
    NSColor(white: 0.10, alpha: 0.80).setFill()
    NSBezierPath(
      roundedRect: CGRect(
        origin: origin, size: CGSize(width: size.width + 24, height: size.height + 14)), xRadius: 7,
      yRadius: 7
    ).fill()
    (text as NSString).draw(
      at: CGPoint(x: origin.x + 12, y: origin.y + 7), withAttributes: attributes)
  }
}
