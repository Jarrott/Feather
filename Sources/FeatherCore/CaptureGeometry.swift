import Foundation

/// 统一使用左上角为原点的图像坐标，避免 Retina 和 AppKit 坐标混用。
public enum CaptureGeometry {
  /// 将任意拖拽方向归一化并限制在边界内；不改变输入，不产生副作用。
  public static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect {
    let rect = CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(end.x - start.x), height: abs(end.y - start.y))
    let clipped = rect.intersection(bounds)
    return clipped.isNull ? .zero : clipped
  }

  /// 将屏幕逻辑点转换成截图像素，向外取整且裁剪到图片边界；无效尺寸返回 nil。
  public static func pixelRect(selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect? {
    guard viewSize.width > 0, viewSize.height > 0,
      imageSize.width > 0, imageSize.height > 0,
      selection.width >= 2, selection.height >= 2,
      [
        selection.minX, selection.minY, selection.width, selection.height,
        viewSize.width, viewSize.height, imageSize.width, imageSize.height,
      ].allSatisfy(\.isFinite)
    else { return nil }
    let scaleX = imageSize.width / viewSize.width
    let scaleY = imageSize.height / viewSize.height
    let rect = CGRect(
      x: selection.minX * scaleX, y: selection.minY * scaleY,
      width: selection.width * scaleX, height: selection.height * scaleY
    )
    .integral.intersection(CGRect(origin: .zero, size: imageSize))
    return rect.isEmpty || rect.isNull ? nil : rect
  }

  /// 返回图片在给定容器中的等比适配区域；无效输入返回零矩形。
  public static func fit(image: CGSize, inside bounds: CGRect) -> CGRect {
    guard image.width > 0, image.height > 0, bounds.width > 0, bounds.height > 0 else {
      return .zero
    }
    let scale = min(bounds.width / image.width, bounds.height / image.height)
    let size = CGSize(width: image.width * scale, height: image.height * scale)
    return CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
  }
}
