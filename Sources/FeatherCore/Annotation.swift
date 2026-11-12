import Foundation

public enum AnnotationTool: String, CaseIterable, Sendable {
  case rectangle, ellipse, arrow, pen, highlight, text, redact, mosaic

  /// 固定工具按键，不随声明顺序变化；新增工具必须显式分配。
  public var shortcut: String {
    switch self {
    case .rectangle: "1"
    case .ellipse: "2"
    case .arrow: "3"
    case .pen: "4"
    case .highlight: "5"
    case .text: "6"
    case .redact: "7"
    case .mosaic: "8"
    }
  }

  public static func forShortcut(_ key: String) -> Self? {
    allCases.first { $0.shortcut == key }
  }
}

/// 独立于界面框架的颜色，所有分量限定为 0...1；仅存储于内存。
public struct InkColor: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(_ red: Double, _ green: Double, _ blue: Double) {
    self.red = min(1, max(0, red))
    self.green = min(1, max(0, green))
    self.blue = min(1, max(0, blue))
  }

  public static let palette: [InkColor] = [
    InkColor(0.96, 0.26, 0.30), InkColor(1, 0.69, 0.16), InkColor(0.10, 0.69, 0.54),
    InkColor(0.22, 0.49, 0.96), InkColor(0.64, 0.37, 0.92), InkColor(1, 1, 1),
  ]
}

/// 使用原始图像像素坐标保存标注；缩放编辑器不会改变导出位置或笔画。
public struct Annotation: Identifiable, Equatable, Sendable {
  public let id: UUID
  public var tool: AnnotationTool
  public var points: [CGPoint]
  public var color: InkColor
  public var lineWidth: CGFloat
  public var text: String
  public var fontSize: CGFloat

  public init(
    tool: AnnotationTool, points: [CGPoint], color: InkColor,
    lineWidth: CGFloat = 4, text: String = "", fontSize: CGFloat? = nil
  ) {
    self.id = UUID()
    self.tool = tool
    self.points = points
    self.color = color
    self.lineWidth = min(80, max(1, lineWidth))
    self.text = String(text.prefix(2000))
    self.fontSize = min(240, max(8, fontSize ?? max(18, self.lineWidth * 5)))
  }

  /// 返回保持身份与样式的平移副本；偏移使用原图像素，不改变原始标注。
  public func translated(by offset: CGPoint) -> Annotation {
    var result = self
    result.points = points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    return result
  }

  public var rect: CGRect {
    guard let start = points.first, let end = points.last else { return .zero }
    return CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(end.x - start.x), height: abs(end.y - start.y))
  }
}

/// 有界编辑历史；统一管理新增、移动、删除、文字编辑和裁剪，最多 200 步，不缓存图片副本。
public struct AnnotationHistory: Sendable {
  public private(set) var annotations: [Annotation] = []
  public private(set) var cropRect: CGRect?
  private enum Edit: Sendable {
    case addition(Annotation)
    case movement(UUID, CGPoint)
    case removal(Annotation, Int)
    case replacement(Annotation, Annotation)
    case crop(CGRect, CGRect)

    func translated(by offset: CGPoint) -> Edit {
      switch self {
      case .addition(let value): .addition(value.translated(by: offset))
      case .removal(let value, let index): .removal(value.translated(by: offset), index)
      case .replacement(let before, let after):
        .replacement(before.translated(by: offset), after.translated(by: offset))
      default: self
      }
    }
  }
  private var applied: [Edit] = []
  private var undone: [Edit] = []
  public var canUndo: Bool { !applied.isEmpty }
  public var canRedo: Bool { !undone.isEmpty }
  public var isFull: Bool { annotations.count >= 200 }

  public init() {}

  /// 添加有效标注；达到上限时返回 false，保留已有内容。
  @discardableResult
  public mutating func append(_ annotation: Annotation) -> Bool {
    guard !isFull, !annotation.points.isEmpty else { return false }
    annotations.append(annotation)
    record(.addition(annotation))
    return true
  }

  /// 平移指定标注，忽略无效身份、非有限或零偏移；一次调用记录一步。
  @discardableResult
  public mutating func move(id: UUID, by offset: CGPoint) -> Bool {
    guard offset.x.isFinite, offset.y.isFinite, offset != .zero,
      let index = annotations.firstIndex(where: { $0.id == id })
    else { return false }
    annotations[index] = annotations[index].translated(by: offset)
    record(.movement(id, offset))
    return true
  }

  /// 删除单个标注并记住原层级，以便撤销后准确恢复；无效 ID 无副作用。
  @discardableResult
  public mutating func remove(id: UUID) -> Bool {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
    record(.removal(annotations.remove(at: index), index))
    return true
  }

  /// 替换同一身份的标注，用于文字和字号编辑；相同内容不会消耗历史。
  @discardableResult
  public mutating func replace(_ annotation: Annotation) -> Bool {
    guard let index = annotations.firstIndex(where: { $0.id == annotation.id }),
      annotations[index] != annotation
    else { return false }
    let previous = annotations[index]
    annotations[index] = annotation
    record(.replacement(previous, annotation))
    return true
  }

  /// 拖动期间更新裁剪坐标并平移全部历史；初次设置仅建立原点，不记录撤销。
  public mutating func previewCrop(_ rect: CGRect) {
    if let old = cropRect {
      translate(by: CGPoint(x: old.minX - rect.minX, y: old.minY - rect.minY))
    }
    cropRect = rect
  }

  /// 抬起时将整段裁剪拖动记为一步；像素图由调用方从冻结原图重建。
  public mutating func commitCrop(from previous: CGRect) {
    guard let current = cropRect, previous != current else { return }
    record(.crop(previous, current))
  }

  /// 撤回最近编辑；裁剪撤销同步迁移标注及历史，保持原屏幕位置。
  public mutating func undo() {
    guard let edit = applied.popLast() else { return }
    switch edit {
    case .addition(let annotation): annotations.removeAll { $0.id == annotation.id }
    case .movement(let id, let offset): applyMove(id: id, by: CGPoint(x: -offset.x, y: -offset.y))
    case .removal(let annotation, let index):
      annotations.insert(annotation, at: min(index, annotations.count))
    case .replacement(let before, _): applyReplacement(before)
    case .crop(let before, _): previewCrop(before)
    }
    undone.append(edit)
  }

  /// 恢复最近撤回的编辑；保持层级、裁剪范围及文字样式一致。
  public mutating func redo() {
    guard let edit = undone.popLast() else { return }
    switch edit {
    case .addition(let annotation): annotations.append(annotation)
    case .movement(let id, let offset): applyMove(id: id, by: offset)
    case .removal(let annotation, _): annotations.removeAll { $0.id == annotation.id }
    case .replacement(_, let after): applyReplacement(after)
    case .crop(_, let after): previewCrop(after)
    }
    applied.append(edit)
  }

  /// 改变裁剪原点时迁移标注以及绝对坐标历史；移动偏移和全图裁剪矩形保持不变。
  public mutating func translate(by offset: CGPoint) {
    annotations = annotations.map { $0.translated(by: offset) }
    applied = applied.map { $0.translated(by: offset) }
    undone = undone.map { $0.translated(by: offset) }
  }

  private mutating func record(_ edit: Edit) {
    applied.append(edit)
    if applied.count > 200 { applied.removeFirst(applied.count - 200) }
    undone.removeAll()
  }

  private mutating func applyMove(id: UUID, by offset: CGPoint) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
    annotations[index] = annotations[index].translated(by: offset)
  }

  private mutating func applyReplacement(_ annotation: Annotation) {
    guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
    annotations[index] = annotation
  }
}
