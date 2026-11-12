import AppKit

/// 用户主动发起的截图方式；重复区域只记几何信息，不持久化图像。
enum CaptureMode { case region, fullScreen, lastRegion, window }

/// 上次成功输出的显示器与相对范围；显示器变化时按新尺寸映射，非法/已断开范围不会截错屏幕。
struct SavedRegion: Codable, Equatable {
  let displayID: UInt32
  let normalizedRect: CGRect

  func rect(in size: CGSize) -> CGRect? {
    let rect = normalizedRect
    guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite,
      rect.width > 0, rect.height > 0,
      CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect)
    else { return nil }
    return CGRect(
      x: rect.minX * size.width, y: rect.minY * size.height,
      width: rect.width * size.width, height: rect.height * size.height)
  }
}
