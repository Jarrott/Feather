import AppKit
import FeatherCore

/// 单一活动手势；起点、原始裁剪与预览标注随状态一起存在，避免多组可选值互相矛盾。
enum SelectionInteraction {
  case idle
  case selecting(CGPoint)
  case transforming(CGPoint, CGRect, CGRect, SelectionHandle?)
  case drawing(CGPoint, Annotation)
  case movingAnnotation(CGPoint, Annotation, Annotation)
  case text(CGPoint, Annotation?)

  var pending: Annotation? {
    switch self {
    case .drawing(_, let value), .movingAnnotation(_, _, let value): value
    default: nil
    }
  }
}

extension SelectionView {
  /// 所有工具双击确认优先；手柄缩放、标注命中与新绘制按明确次序分派。
  override func mouseDown(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    cancelTextClick()
    finishText(commit: true)
    window?.makeKey()
    window?.makeFirstResponder(self)
    let point = convert(event.locationInWindow, from: nil)
    interaction = .idle
    guard let document else {
      selection = .zero
      interaction = .selecting(point)
      refresh()
      return
    }
    let handle = SelectionHandle.allCases.first {
      let position = $0.point(in: selection)
      return hypot(position.x - point.x, position.y - point.y) <= 8
    }
    if handle == nil, selection.contains(point), event.clickCount == 2 {
      if let clickMark, document.history.annotations.last?.id == clickMark.id {
        document.history = clickMark.history
      }
      clickMark = nil
      document.copy(closeAfter: true)
      refresh()
      return
    }
    clickMark = nil
    if let handle {
      interaction = .transforming(point, selection, pixelRect, handle)
    } else if selection.contains(point) {
      let pixel = imagePoint(point)
      let tolerance =
        6 * max(CGFloat(source.width) / bounds.width, CGFloat(source.height) / bounds.height)
      if !event.modifierFlags.contains(.option),
        let annotation = document.history.annotations.last(where: {
          AnnotationGeometry.contains(pixel, in: $0, tolerance: tolerance)
        })
      {
        selectedAnnotationID = annotation.id
        interaction = .movingAnnotation(point, annotation, annotation)
      } else {
        selectedAnnotationID = nil
        if document.isSelectingRegion {
          interaction = .transforming(point, selection, pixelRect, nil)
        } else if document.tool == .text {
          interaction = .text(point, nil)
        } else {
          interaction = .drawing(
            point,
            Annotation(
              tool: document.tool, points: [pixel],
              color: document.color, lineWidth: document.lineWidth))
        }
      }
    } else {
      selectedAnnotationID = nil
    }
    refresh()
  }

  /// 拖动仅更新活动手势和局部脏区；长画笔达到采样上限后均匀抽稀并提示，继续记录笔尾。
  override func mouseDragged(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    let point = convert(event.locationInWindow, from: nil)
    switch interaction {
    case .idle, .text: return
    case .selecting(let start):
      selection = CaptureGeometry.selection(from: start, to: point, bounds: bounds)
    case .transforming(let start, let original, _, let handle):
      let delta = CGPoint(x: point.x - start.x, y: point.y - start.y)
      changeSelection(
        handle.map { SelectionGeometry.resize(original, handle: $0, by: delta, inside: bounds) }
          ?? SelectionGeometry.move(original, by: delta, inside: bounds))
    case .movingAnnotation(let start, let original, _):
      let offset = AnnotationGeometry.constrainedOffset(
        CGPoint(
          x: (point.x - start.x) * CGFloat(source.width) / bounds.width,
          y: (point.y - start.y) * CGFloat(source.height) / bounds.height),
        for: original, inside: CGRect(origin: .zero, size: pixelRect.size))
      interaction = .movingAnnotation(start, original, original.translated(by: offset))
    case .drawing(let start, var value):
      let pixel = imagePoint(point)
      if value.tool == .pen {
        if let last = value.points.last, hypot(last.x - pixel.x, last.y - pixel.y) < 1 { return }
        if value.points.count >= 20_000 {
          value.points = stride(from: 0, to: value.points.count, by: 2).map { value.points[$0] }
          document?.status = L.text("editor.strokeSimplified")
        }
        value.points.append(pixel)
      } else {
        value.points = [value.points[0], pixel]
      }
      interaction = .drawing(start, value)
    }
    refresh()
  }

  /// 抬起提交一次编辑；首击小标记保留原历史供双击撤回，文字单击延迟以保留双击完成行为。
  override func mouseUp(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    mouseDragged(with: event)
    switch interaction {
    case .movingAnnotation(let start, let original, let pending):
      if let first = original.points.first, let moved = pending.points.first {
        document?.moveAnnotation(
          id: original.id, by: CGPoint(x: moved.x - first.x, y: moved.y - first.y))
      }
      let point = convert(event.locationInWindow, from: nil)
      if original.tool == .text, document?.tool == .text, document?.isSelectingRegion == false,
        hypot(point.x - start.x, point.y - start.y) < 3
      {
        scheduleText(at: original.points[0], existing: original)
      }
    case .text(let start, let existing):
      let point = convert(event.locationInWindow, from: nil)
      if hypot(point.x - start.x, point.y - start.y) < 3 {
        scheduleText(at: imagePoint(start), existing: existing)
      }
    case .transforming(_, _, let original, _): document?.history.commitCrop(from: original)
    case .drawing(let start, let pending):
      if let document {
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
            let end = convert(event.locationInWindow, from: nil)
            if event.clickCount == 1, hypot(end.x - start.x, end.y - start.y) < 3 {
              clickMark = (pending.id, history)
            }
          }
        }
      }
    default: break
    }
    interaction = .idle
    if document == nil, selection.width >= 4, selection.height >= 4 { onSelect?(selection) }
    refresh()
  }

  /// 屏幕变化前落定当前手势和文字，确保外接屏断开时不会遗失正在绘制的内容。
  func preserveInteraction() {
    cancelTextClick()
    finishText(commit: true)
    guard document?.isExporting != true else { return }
    switch interaction {
    case .drawing(_, let value): document?.add(value)
    case .movingAnnotation(_, let before, let after):
      if let first = before.points.first, let last = after.points.first {
        document?.moveAnnotation(
          id: before.id, by: CGPoint(x: last.x - first.x, y: last.y - first.y))
      }
    case .transforming(_, _, let rect, _): document?.history.commitCrop(from: rect)
    default: break
    }
    interaction = .idle
  }

  override func rightMouseDown(with event: NSEvent) {
    guard document?.isExporting != true else { return }
    cancelTextClick()
    onCancel?()
  }
}
