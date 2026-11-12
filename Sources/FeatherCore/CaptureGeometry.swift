import Foundation

/// 统一使用左上角为原点的图像坐标，避免 Retina 和 AppKit 坐标混用。
public enum CaptureGeometry {
  /// 用系统捕捉内容的点尺寸和像素比例计算完整分辨率；无效系统值回退至屏幕几何。
  /// 返回向上取整的像素尺寸，无放大插值；两组输入都无效时返回 nil，避免整数转换崩溃。
  public static func capturePixelSize(
    contentSize: CGSize, pointPixelScale: CGFloat, fallbackSize: CGSize, backingScale: CGFloat
  ) -> CGSize? {
    for (size, scale) in [(contentSize, pointPixelScale), (fallbackSize, backingScale)] {
      let width = size.width * scale
      let height = size.height * scale
      if size.width > 0, size.height > 0, scale > 0,
        width.isFinite, height.isFinite, width > 0, height > 0,
        width < CGFloat(Int.max), height < CGFloat(Int.max)
      {
        return CGSize(width: ceil(width), height: ceil(height))
      }
    }
    return nil
  }

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
    // 消除像素→逻辑点→像素往返的浮点误差，避免重复截图逐次增加一行或一列。
    func aligned(_ value: CGFloat) -> CGFloat {
      abs(value - value.rounded()) < 0.00000001 ? value.rounded() : value
    }
    let left = floor(aligned(selection.minX * scaleX))
    let top = floor(aligned(selection.minY * scaleY))
    let right = ceil(aligned(selection.maxX * scaleX))
    let bottom = ceil(aligned(selection.maxY * scaleY))
    let rect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
      .intersection(CGRect(origin: .zero, size: imageSize))
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
