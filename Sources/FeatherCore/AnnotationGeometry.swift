import AppKit

/// 标注命中、选择边界与拖动约束；输入输出均为原图像素，不改变图像或编辑历史。
@MainActor
public enum AnnotationGeometry {
  /// 文字测量与渲染共用同一字体，确保文字可点击区域与实际输出一致。
  public static func textFont(for annotation: Annotation) -> NSFont {
    NSFont.systemFont(ofSize: max(18, annotation.lineWidth * 5), weight: .semibold)
  }

  /// 返回完整标注的包围盒；画笔计算所有采样点，箭头包括箭头头部，文字按真实字体测量。
  public static func bounds(of annotation: Annotation) -> CGRect {
    guard let start = annotation.points.first else { return .zero }
    if annotation.tool == .text {
      return CGRect(
        origin: start,
        size: (annotation.text as NSString).size(withAttributes: [
          .font: textFont(for: annotation)
        ]))
    }
    if annotation.points.count == 1 { return CGRect(origin: start, size: .zero) }
    let path = outline(of: annotation)
    let rect = path.boundingBoxOfPath
    if annotation.tool == .arrow { return rect.union(arrowHead(of: annotation).boundingBoxOfPath) }
    return rect
  }

  /// 轮廓工具只命中线条，保留空心区域供继续绘制；填充和文字命中内容区域。容差由逻辑点换算。
  public static func contains(_ point: CGPoint, in annotation: Annotation, tolerance: CGFloat)
    -> Bool
  {
    guard !annotation.points.isEmpty else { return false }
    let width = annotation.lineWidth + max(0, tolerance) * 2
    guard bounds(of: annotation).insetBy(dx: -width, dy: -width).contains(point) else {
      return false
    }
    switch annotation.tool {
    case .text, .highlight, .redact:
      return bounds(of: annotation).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    case .pen where annotation.points.count == 1:
      let start = annotation.points[0]
      return hypot(point.x - start.x, point.y - start.y) <= width / 2
    default:
      let stroke = outline(of: annotation).copy(
        strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
      return stroke.contains(point)
        || (annotation.tool == .arrow && arrowHead(of: annotation).contains(point))
    }
  }

  /// 限制拖动使原本可见的标注留在图片内；已被裁剪的标注可向内移，不允许进一步移出。
  public static func constrainedOffset(
    _ offset: CGPoint, for annotation: Annotation, inside image: CGRect
  ) -> CGPoint {
    let rect = bounds(of: annotation)
    return CGPoint(
      x: min(max(offset.x, min(0, image.minX - rect.minX)), max(0, image.maxX - rect.maxX)),
      y: min(max(offset.y, min(0, image.minY - rect.minY)), max(0, image.maxY - rect.maxY)))
  }

  /// 返回与渲染一致的实心箭头路径；无端点时返回空路径，无上下文副作用。
  public static func arrowHead(of annotation: Annotation) -> CGPath {
    let path = CGMutablePath()
    guard let start = annotation.points.first, let end = annotation.points.last else { return path }
    let angle = atan2(end.y - start.y, end.x - start.x)
    let length = max(14, annotation.lineWidth * 4)
    path.move(to: end)
    path.addLine(
      to: CGPoint(
        x: end.x - length * cos(angle - .pi / 6), y: end.y - length * sin(angle - .pi / 6)))
    path.addLine(
      to: CGPoint(
        x: end.x - length * cos(angle + .pi / 6), y: end.y - length * sin(angle + .pi / 6)))
    path.closeSubpath()
    return path
  }

  private static func outline(of annotation: Annotation) -> CGPath {
    let path = CGMutablePath()
    switch annotation.tool {
    case .rectangle, .highlight, .redact: path.addRect(annotation.rect)
    case .ellipse: path.addEllipse(in: annotation.rect)
    default:
      if let start = annotation.points.first {
        path.move(to: start)
        for point in annotation.points.dropFirst() { path.addLine(to: point) }
      }
    }
    return path
  }
}
