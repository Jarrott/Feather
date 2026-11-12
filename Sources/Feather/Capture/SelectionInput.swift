import AppKit
import FeatherCore

extension SelectionView {
  /// 固定键码确认/删除及稳定工具映射；组合键由 performKeyEquivalent 处理。
  override func keyDown(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    cancelTextClick()
    clickMark = nil
    if event.keyCode == 53 {
      onCancel?()
      return
    }
    if event.keyCode == 48 {
      selectNextAnnotation(backward: event.modifierFlags.contains(.shift))
      return
    }
    guard let document else {
      super.keyDown(with: event)
      return
    }
    switch event.keyCode {
    case 36, 76: document.copy(closeAfter: true)
    case 51, 117:
      if let id = selectedAnnotationID { document.deleteAnnotation(id: id) }
    case 120: editSelectedText()
    case 123...126: nudge(keyCode: event.keyCode, modifiers: event.modifierFlags)
    default:
      let modifiers = event.modifierFlags.intersection([.command, .option, .control])
      guard modifiers.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased() else {
        super.keyDown(with: event)
        return
      }
      if key == "v" || key == "0" {
        document.isSelectingRegion = true
      } else if let tool = AnnotationTool.forShortcut(key) {
        document.selectTool(tool)
      } else {
        super.keyDown(with: event)
      }
    }
    refresh()
  }

  /// 编辑快捷键共享文档事务；文字正在编辑时让 NSTextView 处理复制、粘贴、撤销等标准命令。
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if textEditor != nil { return super.performKeyEquivalent(with: event) }
    guard event.modifierFlags.contains(.command), document?.isExporting != true else {
      return super.performKeyEquivalent(with: event)
    }
    if event.charactersIgnoringModifiers?.lowercased() == "a", document == nil {
      onSelect?(bounds)
      return true
    }
    guard let document else { return super.performKeyEquivalent(with: event) }
    cancelTextClick()
    clickMark = nil
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "s": document.save(asNewLocation: event.modifierFlags.contains(.shift), closeAfter: true)
    case "c": document.copy(closeAfter: true)
    case "z": event.modifierFlags.contains(.shift) ? document.redo() : document.undo()
    case "p": document.pin()
    default: return super.performKeyEquivalent(with: event)
    }
    refresh()
    return true
  }

  /// Tab 按图层顺序选标注，播报类型/文字；不拦截 VoiceOver 自身导航键。
  func selectNextAnnotation(backward: Bool) {
    guard let annotations = document?.history.annotations, !annotations.isEmpty else { return }
    let current = annotations.firstIndex { $0.id == selectedAnnotationID } ?? (backward ? 0 : -1)
    let next = (current + (backward ? -1 : 1) + annotations.count) % annotations.count
    selectedAnnotationID = annotations[next].id
    refresh()
    NSAccessibility.post(element: self, notification: .valueChanged)
  }

  /// 方向键移动所选标注或选区，Shift 加速；Option+方向键调整选区尺寸，每次均可撤销。
  func nudge(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
    guard let document else { return }
    let amount: CGFloat = modifiers.contains(.shift) ? 10 : 1
    let offset = CGPoint(
      x: keyCode == 123 ? -amount : keyCode == 124 ? amount : 0,
      y: keyCode == 126 ? -amount : keyCode == 125 ? amount : 0)
    if let annotation = document.history.annotations.first(where: { $0.id == selectedAnnotationID })
    {
      document.moveAnnotation(
        id: annotation.id,
        by: AnnotationGeometry.constrainedOffset(
          offset,
          for: annotation, inside: CGRect(origin: .zero, size: pixelRect.size)))
    } else {
      let previous = pixelRect
      if modifiers.contains(.option) {
        changeSelection(
          SelectionGeometry.resize(selection, handle: .bottomRight, by: offset, inside: bounds))
      } else {
        changeSelection(SelectionGeometry.move(selection, by: offset, inside: bounds))
      }
      document.history.commitCrop(from: previous)
    }
    refresh()
    NSAccessibility.post(element: self, notification: .valueChanged)
  }

  /// 对读屏提供可命名动作；全屏框选后可用方向键调整，无需依赖鼠标。
  func installAccessibilityActions() {
    setAccessibilityCustomActions([
      NSAccessibilityCustomAction(
        name: L.text("capture.fullScreen"),
        handler: { [weak self] in
          guard let self, self.document == nil else { return false }
          self.onSelect?(self.bounds)
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("accessibility.next"),
        handler: { [weak self] in
          self?.selectNextAnnotation(backward: false)
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("editor.delete"),
        handler: { [weak self] in
          guard let self, let id = self.selectedAnnotationID else { return false }
          self.document?.deleteAnnotation(id: id)
          self.refresh()
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("editor.editText"),
        handler: { [weak self] in
          self?.editSelectedText()
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("editor.copy"),
        handler: { [weak self] in
          self?.document?.copy(closeAfter: true)
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("editor.save"),
        handler: { [weak self] in
          self?.document?.save(closeAfter: true)
          return true
        }),
      NSAccessibilityCustomAction(
        name: L.text("cancel"),
        handler: { [weak self] in
          guard self?.document?.isExporting != true else { return false }
          self?.onCancel?()
          return true
        }),
    ])
  }

  override func accessibilityValue() -> Any? {
    let dimensions = "\(Int(pixelRect.width)) × \(Int(pixelRect.height))"
    if let selected = document?.history.annotations.first(where: { $0.id == selectedAnnotationID })
    {
      return "\(dimensions), \(selected.tool.title), \(selected.text)"
    }
    return dimensions
  }
}
