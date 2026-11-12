import AppKit
import FeatherCore
import QuartzCore

/// 冻结原图常驻 GPU 图层；遮罩只更新路径，鼠标交互不再重新绘制整张源图。
@MainActor
final class FrozenImageView: NSView {
  let image: CGImage
  let shade = CAShapeLayer()
  override var isFlipped: Bool { true }
  init(image: CGImage, frame: CGRect) {
    self.image = image
    super.init(frame: frame)
    wantsLayer = true
    layer?.contents = image
    layer?.contentsGravity = .resize
    layer?.magnificationFilter = .nearest
    layer?.minificationFilter = .nearest
    shade.fillColor = CGColor(gray: 0, alpha: 0.27)
    shade.fillRule = .evenOdd
    layer?.addSublayer(shade)
    updateShade(selection: .zero)
  }
  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  /// 没有隐式动画；仅替换选择区域孔洞，不复制冻结图像。
  func updateShade(selection: CGRect) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    shade.frame = bounds
    let path = CGMutablePath()
    path.addRect(bounds)
    if !selection.isEmpty { path.addRect(selection) }
    shade.path = path
    CATransaction.commit()
  }
}

/// 透明动态绘制层；AppKit 按脏区调度，事件穿透给交互容器。
@MainActor
final class AnnotationCanvasView: NSView {
  weak var owner: SelectionView?
  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func draw(_ dirtyRect: NSRect) { owner?.drawOverlay(dirtyRect) }
}

extension SelectionView {
  /// 计算标注在屏幕上的影响范围，包含线宽、选中辅助线和阴影。
  func damageRect(_ annotation: Annotation, selection: CGRect? = nil) -> CGRect {
    let scaleX = bounds.width / CGFloat(source.width)
    let scaleY = bounds.height / CGFloat(source.height)
    let rect = AnnotationGeometry.bounds(of: annotation).insetBy(
      dx: -annotation.lineWidth, dy: -annotation.lineWidth)
    let origin = selection ?? self.selection
    return CGRect(
      x: origin.minX + rect.minX * scaleX, y: origin.minY + rect.minY * scaleY,
      width: rect.width * scaleX, height: rect.height * scaleY
    ).insetBy(dx: -10, dy: -10)
  }

  /// 对比上次绘制状态，仅失效新增/改变/删除的标注区域；选区变化才更新遮罩和尺寸文字。
  func invalidateChanges() {
    let annotations = document?.history.annotations ?? []
    let pending = interaction.pending
    let selected = pending ?? annotations.first { $0.id == selectedAnnotationID }
    if renderedSelection != selection {
      background.updateShade(selection: selection)
      if renderedSelection.isEmpty {
        canvas.needsDisplay = true
      } else {
        canvas.setNeedsDisplay(renderedSelection.union(selection).insetBy(dx: -12, dy: -32))
      }
    } else {
      let old = Dictionary(uniqueKeysWithValues: renderedAnnotations.map { ($0.id, $0) })
      let new = Dictionary(uniqueKeysWithValues: annotations.map { ($0.id, $0) })
      for item in renderedAnnotations where new[item.id] != item {
        canvas.setNeedsDisplay(damageRect(item))
      }
      for item in annotations where old[item.id] != item {
        canvas.setNeedsDisplay(damageRect(item))
      }
      if renderedPending != pending {
        if let value = renderedPending { canvas.setNeedsDisplay(damageRect(value)) }
        if let value = pending { canvas.setNeedsDisplay(damageRect(value)) }
      }
      if renderedSelected != selected {
        if let value = renderedSelected { canvas.setNeedsDisplay(damageRect(value)) }
        if let value = selected { canvas.setNeedsDisplay(damageRect(value)) }
      }
    }
    renderedSelection = selection
    renderedAnnotations = annotations
    renderedSelected = selected
    renderedPending = pending
  }

  /// 动态层不绘制原图；只遍历与脏区相交的标注，保持导出与预览相同的 CoreGraphics/CoreText 路径。
  func drawOverlay(_ dirtyRect: CGRect) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    context.saveGState()
    defer { context.restoreGState() }
    context.clip(to: dirtyRect)
    if let document {
      context.saveGState()
      context.clip(to: selection)
      context.translateBy(x: selection.minX, y: selection.minY)
      context.scaleBy(
        x: bounds.width / CGFloat(source.width), y: bounds.height / CGFloat(source.height))
      let pending = interaction.pending
      let redactions = document.history.annotations.map { pending?.id == $0.id ? pending! : $0 }
        .filter { $0.tool == .redact }.map(\.rect)
      for annotation in document.history.annotations where annotation.id != editingAnnotation?.id {
        let value = pending?.id == annotation.id ? pending! : annotation
        if damageRect(value).intersects(dirtyRect) {
          AnnotationRenderer.draw(value, in: context, image: document.image, redactions: redactions)
        }
      }
      if let pending, !document.history.annotations.contains(where: { $0.id == pending.id }),
        damageRect(pending).intersects(dirtyRect)
      {
        AnnotationRenderer.draw(pending, in: context, image: document.image, redactions: redactions)
      }
      if let selected = pending
        ?? document.history.annotations.first(where: { $0.id == selectedAnnotationID })
      {
        let scale = CGFloat(source.width) / bounds.width
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        context.setShadow(offset: .zero, blur: 2 * scale, color: CGColor(gray: 0, alpha: 1))
        context.setLineWidth(scale)
        context.setLineDash(phase: 0, lengths: [3 * scale, 3 * scale])
        context.stroke(
          AnnotationGeometry.bounds(of: selected).insetBy(dx: -4 * scale, dy: -4 * scale))
      }
      context.restoreGState()
    }
    if !selection.isEmpty {
      CaptureStyle.selectionColor.setStroke()
      let border = NSBezierPath(rect: selection)
      border.lineWidth = 1
      border.stroke()
      CaptureStyle.selectionColor.setFill()
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
    } else if document == nil {
      drawInstruction()
    }
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
