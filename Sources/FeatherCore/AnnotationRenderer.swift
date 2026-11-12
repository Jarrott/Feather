import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 编辑预览和 PNG 导出共用的渲染器，调用方必须提供左上角原点的 CGContext。
@MainActor
public enum AnnotationRenderer {
  /// 绘制一个像素坐标标注；不会修改上下文状态。遮盖使用不可逆的实色矩形。
  public static func draw(_ annotation: Annotation, in context: CGContext) {
    guard let start = annotation.points.first else { return }
    let end = annotation.points.last ?? start
    let color = NSColor(
      srgbRed: annotation.color.red, green: annotation.color.green,
      blue: annotation.color.blue, alpha: 1)
    context.saveGState()
    defer { context.restoreGState() }
    context.setStrokeColor(color.cgColor)
    context.setFillColor(color.cgColor)
    context.setLineWidth(annotation.lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    switch annotation.tool {
    case .rectangle:
      context.stroke(annotation.rect)
    case .ellipse:
      context.strokeEllipse(in: annotation.rect)
    case .arrow:
      context.move(to: start)
      context.addLine(to: end)
      context.strokePath()
      context.addPath(AnnotationGeometry.arrowHead(of: annotation))
      context.fillPath()
    case .pen:
      if annotation.points.count == 1 {
        let width = annotation.lineWidth
        context.fillEllipse(
          in: CGRect(
            x: start.x - width / 2, y: start.y - width / 2,
            width: width, height: width))
      } else {
        context.addLines(between: annotation.points)
        context.strokePath()
      }
    case .highlight:
      context.setAlpha(0.30)
      context.fill(annotation.rect)
    case .redact:
      context.setFillColor(NSColor.black.cgColor)
      context.fill(annotation.rect.integral)
    case .text:
      let graphics = NSGraphicsContext(cgContext: context, flipped: true)
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = graphics
      let attributes: [NSAttributedString.Key: Any] = [
        .font: AnnotationGeometry.textFont(for: annotation),
        .foregroundColor: color,
      ]
      (annotation.text as NSString).draw(at: start, withAttributes: attributes)
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  /// 以原始像素和颜色空间导出 PNG；无标注时直接编码原图，避免额外全图拷贝与颜色转换。
  /// 有标注时只合成一次，RGB 图片保留原色域；内存分配或编码失败抛出英文错误，不写磁盘。
  public static func png(image: CGImage, annotations: [Annotation]) throws -> Data {
    if annotations.isEmpty { return try encodePNG(image) }
    let colorSpace =
      image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
      ?? CGColorSpace(name: CGColorSpace.sRGB)!
    guard
      let context = CGContext(
        data: nil, width: image.width, height: image.height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ExportError.renderFailed }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    context.translateBy(x: 0, y: CGFloat(image.height))
    context.scaleBy(x: 1, y: -1)
    for annotation in annotations { draw(annotation, in: context) }
    guard let output = context.makeImage() else { throw ExportError.renderFailed }
    return try encodePNG(output)
  }

  /// 将像素图及其颜色配置交给 ImageIO 无损编码；不重采样、不强制转成 sRGB。
  private static func encodePNG(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data, UTType.png.identifier as CFString, 1, nil)
    else { throw ExportError.renderFailed }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ExportError.renderFailed }
    return data as Data
  }
}
