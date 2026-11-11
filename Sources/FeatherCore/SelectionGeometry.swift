import Foundation

/// 选区的八个边缘调整点；枚举不持有 UI 或修改任何选区状态。
public enum SelectionHandle: CaseIterable, Sendable {
  case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

  /// 返回指定逻辑选区的角点或边中点；使用左上角原点，不改变输入矩形。
  public func point(in rect: CGRect) -> CGPoint {
    switch self {
    case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
    case .top: CGPoint(x: rect.midX, y: rect.minY)
    case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
    case .right: CGPoint(x: rect.maxX, y: rect.midY)
    case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
    case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
    case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
    case .left: CGPoint(x: rect.minX, y: rect.midY)
    }
  }
}

/// 悬浮截图选区的纯几何计算；输入和输出均使用当前显示器局部逻辑点。
public enum SelectionGeometry {
  /// 保持选区大小移动并限制到屏幕边界，不产生副作用。
  public static func move(_ rect: CGRect, by delta: CGPoint, inside bounds: CGRect) -> CGRect {
    CGRect(
      x: min(max(bounds.minX, rect.minX + delta.x), bounds.maxX - rect.width),
      y: min(max(bounds.minY, rect.minY + delta.y), bounds.maxY - rect.height),
      width: rect.width, height: rect.height)
  }

  /// 移动指定手柄，固定对边并保留最小 4 点宽高；不允许翻转或越出屏幕。
  public static func resize(
    _ rect: CGRect, handle: SelectionHandle, by delta: CGPoint, inside bounds: CGRect
  ) -> CGRect {
    var left = rect.minX
    var right = rect.maxX
    var top = rect.minY
    var bottom = rect.maxY
    if [.topLeft, .left, .bottomLeft].contains(handle) {
      left = min(right - 4, max(bounds.minX, left + delta.x))
    }
    if [.topRight, .right, .bottomRight].contains(handle) {
      right = max(left + 4, min(bounds.maxX, right + delta.x))
    }
    if [.topLeft, .top, .topRight].contains(handle) {
      top = min(bottom - 4, max(bounds.minY, top + delta.y))
    }
    if [.bottomLeft, .bottom, .bottomRight].contains(handle) {
      bottom = max(top + 4, min(bounds.maxY, bottom + delta.y))
    }
    return CGRect(x: left, y: top, width: right - left, height: bottom - top)
  }

  /// 工具条优先放在选区下方，其次上方；空间不足时放入屏内，避免离屏不可点击。
  public static func toolbarFrame(selection: CGRect, size: CGSize, bounds: CGRect) -> CGRect {
    let width = min(size.width, max(0, bounds.width - 24))
    let x = max(bounds.minX + 12, min(selection.midX - width / 2, bounds.maxX - width - 12))
    let below = selection.maxY + 14
    let above = selection.minY - size.height - 14
    let y = below + size.height <= bounds.maxY - 12 ? below : max(bounds.minY + 12, above)
    return CGRect(
      x: x, y: min(y, bounds.maxY - size.height - 12), width: width, height: size.height)
  }

  /// 属性浮层优先放在工具条远离选区的一侧，空间不足时换侧并限制到屏内。
  /// 全部几何参数使用局部逻辑点；preferAbove 指定优先上方，不改变工具条、选区或图像。
  public static func optionsFrame(
    toolbar: CGRect, size: CGSize, bounds: CGRect, preferAbove: Bool = false
  ) -> CGRect {
    let width = min(size.width, max(0, bounds.width - 24))
    let height = min(size.height, max(0, bounds.height - 24))
    let x = max(bounds.minX + 12, min(toolbar.minX, bounds.maxX - width - 12))
    let below = toolbar.maxY
    let above = toolbar.minY - height
    let y: CGFloat
    if preferAbove && above >= bounds.minY + 12 {
      y = above
    } else if below + height <= bounds.maxY - 12 {
      y = below
    } else {
      y = above
    }
    return CGRect(
      x: x, y: max(bounds.minY + 12, min(y, bounds.maxY - height - 12)),
      width: width, height: height)
  }
}
