import Foundation

public enum AnnotationTool: String, CaseIterable, Sendable {
  case rectangle, ellipse, arrow, pen, highlight, text, redact
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

  public init(
    tool: AnnotationTool, points: [CGPoint], color: InkColor,
    lineWidth: CGFloat = 4, text: String = ""
  ) {
    self.id = UUID()
    self.tool = tool
    self.points = points
    self.color = color
    self.lineWidth = min(80, max(1, lineWidth))
    self.text = String(text.prefix(2000))
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

/// 有界编辑历史；最多 200 个标注和最近 200 步操作，移动只记录偏移，不复制整条画笔路径。
/// 删除记录原位置，撤销后按原图层顺序恢复。
public struct AnnotationHistory: Sendable {
  public private(set) var annotations: [Annotation] = []
  private enum Edit: Sendable {
    case addition(Annotation)
    case movement(UUID, CGPoint)
    case removal(Annotation, index: Int)

    func translated(by offset: CGPoint) -> Edit {
      switch self {
      case .addition(let annotation): .addition(annotation.translated(by: offset))
      case .removal(let annotation, let index):
        .removal(annotation.translated(by: offset), index: index)
      case .movement: self
      }
    }
  }
  private var applied: [Edit] = []
  private var undone: [Edit] = []
  public var canUndo: Bool { !applied.isEmpty }
  public var canRedo: Bool { !undone.isEmpty }
  public var isFull: Bool { annotations.count >= 200 }

  public init() {}

  /// 添加有效标注；达到上限时返回 false，不静默删除已有标注。
  @discardableResult
  public mutating func append(_ annotation: Annotation) -> Bool {
    guard !isFull, !annotation.points.isEmpty else { return false }
    annotations.append(annotation)
    record(.addition(annotation))
    return true
  }

  /// 平移指定标注并记为一步编辑；身份、顺序和样式不变，无效 ID、非有限或零偏移返回 false。
  @discardableResult
  public mutating func move(id: UUID, by offset: CGPoint) -> Bool {
    guard offset.x.isFinite, offset.y.isFinite, offset != .zero,
      let index = annotations.firstIndex(where: { $0.id == id })
    else { return false }
    annotations[index] = annotations[index].translated(by: offset)
    record(.movement(id, offset))
    return true
  }

  /// 删除指定标注并记为一步编辑；撤销时恢复到原图层位置，无效 ID 返回 false。
  @discardableResult
  public mutating func remove(id: UUID) -> Bool {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
    let annotation = annotations.remove(at: index)
    record(.removal(annotation, index: index))
    return true
  }

  /// 撤回最近一次新增、移动或删除；空栈时无副作用。
  public mutating func undo() {
    guard let edit = applied.popLast() else { return }
    switch edit {
    case .addition(let annotation): annotations.removeAll { $0.id == annotation.id }
    case .movement(let id, let offset): applyMove(id: id, by: CGPoint(x: -offset.x, y: -offset.y))
    case .removal(let annotation, let index):
      annotations.insert(annotation, at: min(index, annotations.count))
    }
    undone.append(edit)
  }

  /// 恢复最近一次撤回的编辑，保留标注顺序；空栈时无副作用。
  public mutating func redo() {
    guard let edit = undone.popLast() else { return }
    switch edit {
    case .addition(let annotation): annotations.append(annotation)
    case .movement(let id, let offset): applyMove(id: id, by: offset)
    case .removal(let annotation, _): annotations.removeAll { $0.id == annotation.id }
    }
    applied.append(edit)
  }

  /// 改变裁剪原点时迁移当前标注与新增记录；移动记录是相对偏移，保持不变。
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
}
