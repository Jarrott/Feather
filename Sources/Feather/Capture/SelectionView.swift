import AppKit
import Combine
import FeatherCore
import SwiftUI

/// 截图覆盖层容器；冻结图、绘图层和控件分离，交互与键盘由独立扩展维护。
@MainActor
final class SelectionView: NSView {
  var onSelect: ((CGRect) -> Void)?
  var onCancel: (() -> Void)?
  let source: CGImage
  var selection = CGRect.zero
  var pixelRect = CGRect.zero
  var document: EditorDocument?
  var toolbar: NSHostingView<CaptureToolbar>?
  var toolOptions: NSHostingView<CaptureToolOptions>?
  var observation: AnyCancellable?
  var interaction = SelectionInteraction.idle
  var selectedAnnotationID: UUID?
  var clickMark: (id: UUID, history: AnnotationHistory)?
  var textClickTask: Task<Void, Never>?
  let requestText: (@MainActor () -> String?)?
  var textEditor: InlineTextEditor?
  var editingAnnotation: Annotation?
  let background: FrozenImageView
  let canvas = AnnotationCanvasView()
  var renderedAnnotations: [Annotation] = []
  var renderedSelection = CGRect.zero
  var renderedSelected: Annotation?
  var renderedPending: Annotation?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }

  /// 原图只装入背景图层一次；可注入文字输入器供测试，实际使用原位 NSTextView。
  init(image: CGImage, frame: CGRect, requestText: (@MainActor () -> String?)? = nil) {
    source = image
    self.requestText = requestText
    background = FrozenImageView(image: image, frame: CGRect(origin: .zero, size: frame.size))
    super.init(frame: frame)
    wantsLayer = true
    background.autoresizingMask = [.width, .height]
    addSubview(background)
    canvas.frame = bounds
    canvas.autoresizingMask = [.width, .height]
    canvas.owner = self
    addSubview(canvas)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel(L.text("editor.title"))
    setAccessibilityHelp(L.text("accessibility.help"))
    installAccessibilityActions()
  }
  required init?(coder: NSCoder) { nil }

  /// 将框选结果接入编辑文档；裁剪撤销使用同一冻结源图，控件不进入输出。
  func beginEditing(_ document: EditorDocument, pixelRect: CGRect) {
    self.document = document
    self.pixelRect = pixelRect
    document.configureCrop(source: source, rect: pixelRect)
    document.commitText = { [weak self] in
      self?.cancelTextClick()
      self?.finishText(commit: true)
    }
    selection = logicalRect(pixelRect)
    let toolbar = NSHostingView(
      rootView: CaptureToolbar(
        document: document,
        onCancel: { [weak self] in self?.onCancel?() }))
    self.toolbar = toolbar
    addSubview(toolbar)
    let options = NSHostingView(rootView: CaptureToolOptions(document: document))
    toolOptions = options
    addSubview(options)
    observation = document.objectWillChange.sink { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        if self.document?.isExporting == true { self.cancelTextClick() }
        self.textEditor?.setStyle(
          size: self.displayFontSize, color: self.document?.color ?? .palette[0])
        self.refresh()
      }
    }
    refresh()
  }

  /// 仅对变化的标注、选框及辅助线计算脏区；浮层只在布局变化时移动。
  func refresh() {
    if let rect = document?.history.cropRect {
      pixelRect = rect
      selection = logicalRect(rect)
    }
    if let document {
      if !document.history.annotations.contains(where: { $0.id == selectedAnnotationID }) {
        selectedAnnotationID = nil
      }
      let frame = SelectionGeometry.toolbarFrame(
        selection: selection,
        size: CaptureToolbar.preferredSize, bounds: bounds)
      if toolbar?.frame != frame { toolbar?.frame = frame }
      if let size = CaptureToolOptions.preferredSize(for: document) {
        toolOptions?.isHidden = false
        let optionsFrame = SelectionGeometry.optionsFrame(
          toolbar: frame, size: size,
          bounds: bounds, preferAbove: frame.maxY <= selection.minY)
        if toolOptions?.frame != optionsFrame { toolOptions?.frame = optionsFrame }
      } else {
        toolOptions?.isHidden = true
      }
    }
    invalidateChanges()
    window?.invalidateCursorRects(for: self)
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    if document != nil {
      finishText(commit: true)
      refresh()
    }
    background.updateShade(selection: selection)
    canvas.needsDisplay = true
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
    if let document {
      addCursorRect(
        selection,
        cursor: document.isSelectingRegion
          ? .openHand : document.tool == .text ? .iBeam : .crosshair)
      for handle in SelectionHandle.allCases {
        let point = handle.point(in: selection)
        let cursor: NSCursor =
          [.top, .bottom].contains(handle)
          ? .resizeUpDown
          : [.left, .right].contains(handle) ? .resizeLeftRight : .crosshair
        addCursorRect(CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12), cursor: cursor)
      }
    }
    for control in [toolbar as NSView?, toolOptions as NSView?, textEditor].compactMap({ $0 })
    where !control.isHidden {
      addCursorRect(control.frame, cursor: .arrow)
    }
  }

  /// 对逻辑选区进行像素对齐；拖动只预览，结束时记录一次裁剪编辑。
  func changeSelection(_ rect: CGRect) {
    guard let document, let pixels = cropRect(rect), pixels != pixelRect else { return }
    document.previewCrop(pixels)
    pixelRect = pixels
    selection = logicalRect(pixels)
  }

  func cropRect(_ selection: CGRect) -> CGRect? {
    CaptureGeometry.pixelRect(
      selection: selection, viewSize: bounds.size,
      imageSize: CGSize(width: source.width, height: source.height))
  }
  func logicalRect(_ pixels: CGRect) -> CGRect {
    let x = bounds.width / CGFloat(source.width)
    let y = bounds.height / CGFloat(source.height)
    return CGRect(
      x: pixels.minX * x, y: pixels.minY * y, width: pixels.width * x, height: pixels.height * y)
  }
  func imagePoint(_ point: CGPoint) -> CGPoint {
    CGPoint(
      x: min(
        pixelRect.width, max(0, (point.x - selection.minX) * CGFloat(source.width) / bounds.width)),
      y: min(
        pixelRect.height,
        max(0, (point.y - selection.minY) * CGFloat(source.height) / bounds.height)))
  }

  func cancelTextClick() {
    textClickTask?.cancel()
    textClickTask = nil
  }

  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil {
      cancelTextClick()
      finishText(commit: false)
    }
    super.viewWillMove(toWindow: newWindow)
  }
}
