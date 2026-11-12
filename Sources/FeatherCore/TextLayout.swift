import CoreGraphics
import CoreText
import Foundation

/// 线程独立的文字布局；每次调用创建自身排版对象，预览、命中与后台导出使用同一字体及行距。
public enum TextLayout {
  /// 返回独立字号的系统字体；CoreText 负责中文和其他字符的字体回退。
  public static func font(size: CGFloat) -> CTFont {
    CTFontCreateUIFontForLanguage(.emphasizedSystem, min(240, max(8, size)), nil)
      ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
  }

  private static func attributed(_ annotation: Annotation) -> CFAttributedString {
    let color = annotation.color
    let attributes: [NSAttributedString.Key: Any] = [
      NSAttributedString.Key(kCTFontAttributeName as String): font(size: annotation.fontSize),
      NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(
        srgbRed: color.red, green: color.green, blue: color.blue, alpha: 1),
    ]
    return NSAttributedString(string: annotation.text, attributes: attributes)
  }

  /// 测量多行文字的原图像素尺寸；排版不共享可变对象，不访问 AppKit 或主线程。
  public static func size(of annotation: Annotation) -> CGSize {
    let setter = CTFramesetterCreateWithAttributedString(attributed(annotation))
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
      setter, CFRange(location: 0, length: 0), nil,
      CGSize(width: 1_000_000, height: 1_000_000), nil)
    return CGSize(width: ceil(size.width) + 1, height: ceil(size.height) + 1)
  }

  /// 在左上原点上下文绘制完整文字；局部翻转 CoreText 坐标，恢复所有上下文状态。
  public static func draw(_ annotation: Annotation, in context: CGContext) {
    guard let point = annotation.points.first, !annotation.text.isEmpty else { return }
    let setter = CTFramesetterCreateWithAttributedString(attributed(annotation))
    let size = size(of: annotation)
    let frame = CTFramesetterCreateFrame(
      setter, CFRange(location: 0, length: 0),
      CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
    context.saveGState()
    defer { context.restoreGState() }
    context.translateBy(x: point.x, y: point.y + size.height)
    context.scaleBy(x: 1, y: -1)
    context.textMatrix = .identity
    CTFrameDraw(frame, context)
  }
}
