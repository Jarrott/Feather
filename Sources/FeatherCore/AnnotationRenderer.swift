import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 编辑预览和 PNG 导出共用的渲染器，调用方必须提供左上角原点的 CGContext。
public enum AnnotationRenderer {
  /// 绘制一个像素坐标标注；不会修改上下文状态。遮盖使用不可逆的实色矩形。
  public static func draw(
    _ annotation: Annotation, in context: CGContext, image: CGImage? = nil,
    redactions: [CGRect] = []
  ) {
    guard let start = annotation.points.first else { return }
    let end = annotation.points.last ?? start
    let color = CGColor(
      srgbRed: annotation.color.red, green: annotation.color.green,
      blue: annotation.color.blue, alpha: 1)
    context.saveGState()
    defer { context.restoreGState() }
    context.setStrokeColor(color)
    context.setFillColor(color)
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
      context.setFillColor(CGColor(gray: 0, alpha: 1))
      context.fill(annotation.rect.integral)
    case .text:
      TextLayout.draw(annotation, in: context)
    case .mosaic:
      if let image { drawMosaic(annotation.rect, image: image, in: context) }
      // 马赛克从源图取样时仍保持所有纯黑遮盖，不能重新暴露被遮盖的原始内容。
      context.setFillColor(CGColor(gray: 0, alpha: 1))
      for rect in redactions {
        let protected = rect.integral.intersection(annotation.rect.integral)
        if !protected.isEmpty { context.fill(protected) }
      }
    }
  }

  /// 对选定区域做块状降采样；仅处理区域像素，预览和导出使用同一路径，纯黑遮盖仍独立保留。
  private static func drawMosaic(_ rect: CGRect, image: CGImage, in context: CGContext) {
    context.saveGState()
    defer { context.restoreGState() }
    let clipped = rect.integral.intersection(
      CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !clipped.isEmpty, let crop = image.cropping(to: clipped),
      let small = CGContext(
        data: nil, width: max(1, Int(clipped.width / 18)),
        height: max(1, Int(clipped.height / 18)), bitsPerComponent: 8, bytesPerRow: 0,
        space: image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
          ?? CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return }
    small.interpolationQuality = .low
    small.draw(crop, in: CGRect(x: 0, y: 0, width: small.width, height: small.height))
    guard let pixels = small.makeImage() else { return }
    context.interpolationQuality = .none
    context.translateBy(x: clipped.minX, y: clipped.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(pixels, in: CGRect(origin: .zero, size: clipped.size))
  }

  /// 以原始像素和颜色空间导出 PNG；无标注时直接编码原图，避免额外全图拷贝与颜色转换。
  /// 有标注时只合成一次，RGB 图片保留原色域；内存分配或编码失败抛出英文错误，不写磁盘。
  public static func png(image: CGImage, annotations: [Annotation]) throws -> Data {
    try encodePNG(composite(image: image, annotations: annotations))
  }

  /// 在原图色域合成全部标注并返回位图；无标注时直接返回原图，不做拷贝。
  /// 贴图等只需位图的场景可直接使用，避免 PNG 编码再解码。
  public static func composite(image: CGImage, annotations: [Annotation]) throws -> CGImage {
    if annotations.isEmpty { return image }
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
    let redactions = annotations.filter { $0.tool == .redact }.map(\.rect)
    for annotation in annotations {
      draw(annotation, in: context, image: image, redactions: redactions)
    }
    guard let output = context.makeImage() else { throw ExportError.renderFailed }
    return output
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
