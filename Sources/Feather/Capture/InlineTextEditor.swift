import AppKit
import FeatherCore

/// 原位文字编辑器，原生文本系统支持输入法、粘贴与多行；提交/取消回调不直接改动文档。
@MainActor
final class InlineTextEditor: NSView, NSTextViewDelegate {
  let textView = NSTextView()
  var onFinish: ((Bool) -> Void)?
  private let hint = NSTextField(labelWithString: L.text("editor.textHint"))
  override var isFlipped: Bool { true }

  init(frame: CGRect, text: String, size: CGFloat, color: InkColor) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
    layer?.borderColor = CaptureStyle.selectionColor.cgColor
    layer?.borderWidth = 1
    layer?.cornerRadius = 4
    let scroll = NSScrollView(
      frame: CGRect(x: 4, y: 4, width: frame.width - 8, height: frame.height - 30))
    scroll.hasVerticalScroller = true
    scroll.autoresizingMask = [.width, .height]
    textView.frame = scroll.bounds
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.textContainer?.widthTracksTextView = true
    textView.autoresizingMask = [.width]
    textView.delegate = self
    textView.string = text
    textView.setAccessibilityLabel(L.text("editor.textTitle"))
    scroll.documentView = textView
    addSubview(scroll)
    hint.font = .systemFont(ofSize: 10)
    hint.textColor = .secondaryLabelColor
    hint.frame = CGRect(x: 8, y: frame.height - 24, width: frame.width - 16, height: 18)
    addSubview(hint)
    setStyle(size: size, color: color)
  }
  required init?(coder: NSCoder) { nil }

  /// 仅改变当前输入字体，字号为屏幕逻辑点；文档独立保存原图像素字号。
  func setStyle(size: CGFloat, color: InkColor) {
    textView.font = NSFont.systemFont(ofSize: size, weight: .semibold)
    textView.textColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1)
  }

  func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
      if textView.hasMarkedText() { return false }
      onFinish?(false)
      return true
    }
    if commandSelector == #selector(NSResponder.insertNewline(_:)),
      NSApp.currentEvent?.modifierFlags.contains(.command) == true, !textView.hasMarkedText()
    {
      onFinish?(true)
      return true
    }
    return false
  }

  /// 限制提交长度，保留原生输入法组合过程；超过限制给出可见提示，避免静默截断。
  func textView(
    _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    guard let replacementString else { return true }
    let value = (textView.string as NSString).replacingCharacters(
      in: affectedCharRange, with: replacementString)
    guard value.count <= 2000 else {
      hint.stringValue = L.text("editor.textLimit")
      return false
    }
    hint.stringValue = L.text("editor.textHint")
    return true
  }
}

extension SelectionView {
  var displayFontSize: CGFloat { (document?.fontSize ?? 28) * bounds.width / CGFloat(source.width) }

  /// 首击等待双击间隔，任何第二击、工具切换或关闭均可取消；不使用常驻定时器。
  func scheduleText(at point: CGPoint, existing: Annotation? = nil) {
    textClickTask = Task { @MainActor [weak self] in
      do { try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval)) } catch { return }
      guard !Task.isCancelled, let self, self.window != nil,
        let document = self.document, !document.isExporting,
        !document.isSelectingRegion, document.tool == .text
      else { return }
      self.textClickTask = nil
      self.beginText(at: point, existing: existing)
    }
  }

  /// F2 或读屏动作重新编辑选中文字；保持身份、层级，提交后作为一次替换进入历史。
  func editSelectedText() {
    guard let value = document?.history.annotations.first(where: { $0.id == selectedAnnotationID }),
      value.tool == .text, let point = value.points.first
    else { return }
    beginText(at: point, existing: value)
  }

  func beginText(at point: CGPoint, existing: Annotation?) {
    guard let document, !document.isExporting else { return }
    finishText(commit: true)
    var annotation =
      existing
      ?? Annotation(
        tool: .text, points: [point], color: document.color,
        lineWidth: document.lineWidth, fontSize: document.fontSize)
    if let requestText {
      guard let value = requestText(),
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else { return }
      annotation.text = String(value.prefix(2000))
      if existing != nil { document.history.replace(annotation) } else { document.add(annotation) }
      selectedAnnotationID = annotation.id
      refresh()
      return
    }
    if let existing {
      document.fontSize = existing.fontSize
      document.color = existing.color
    }
    editingAnnotation = annotation
    let x = selection.minX + point.x * bounds.width / CGFloat(source.width)
    let y = selection.minY + point.y * bounds.height / CGFloat(source.height)
    let size = CGSize(width: min(340, bounds.width - 16), height: min(160, bounds.height - 16))
    let editor = InlineTextEditor(
      frame: CGRect(
        x: min(max(8, x), bounds.maxX - size.width - 8),
        y: min(max(8, y), bounds.maxY - size.height - 8), width: size.width, height: size.height),
      text: annotation.text, size: displayFontSize, color: annotation.color)
    editor.onFinish = { [weak self] commit in self?.finishText(commit: commit) }
    textEditor = editor
    addSubview(editor)
    window?.makeFirstResponder(editor.textView)
    canvas.setNeedsDisplay(damageRect(annotation))
  }

  /// 完成内联编辑；取消不变更历史，空字符串删除已有文字，输入长度/字号受模型约束。
  func finishText(commit: Bool) {
    guard let editor = textEditor, var annotation = editingAnnotation, let document else { return }
    textEditor = nil
    editingAnnotation = nil
    editor.onFinish = nil
    if commit {
      let value = editor.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
      let exists = document.history.annotations.contains { $0.id == annotation.id }
      if value.isEmpty {
        if exists { document.deleteAnnotation(id: annotation.id) }
      } else {
        annotation.text = String(value.prefix(2000))
        annotation.fontSize = document.fontSize
        annotation.color = document.color
        if exists { document.history.replace(annotation) } else { document.add(annotation) }
        selectedAnnotationID = annotation.id
      }
    }
    editor.removeFromSuperview()
    window?.makeFirstResponder(self)
    canvas.setNeedsDisplay(damageRect(annotation))
    refresh()
  }
}
