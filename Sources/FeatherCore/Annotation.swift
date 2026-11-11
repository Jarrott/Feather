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

  public var rect: CGRect {
    guard let start = points.first, let end = points.last else { return .zero }
    return CGRect(
      x: min(start.x, end.x), y: min(start.y, end.y),
      width: abs(end.x - start.x), height: abs(end.y - start.y))
  }
}

/// 值类型撤销栈；新增标注清除重做分支，最多保留 200 个标注以限制内存。
public struct AnnotationHistory: Sendable {
  public private(set) var annotations: [Annotation] = []
  private var undone: [Annotation] = []
  public var canUndo: Bool { !annotations.isEmpty }
  public var canRedo: Bool { !undone.isEmpty }
  public var isFull: Bool { annotations.count >= 200 }

  public init() {}

  /// 添加有效标注；达到上限时返回 false，不静默删除已有标注。
  @discardableResult
  public mutating func append(_ annotation: Annotation) -> Bool {
    guard !isFull, !annotation.points.isEmpty else { return false }
    annotations.append(annotation)
    undone.removeAll()
    return true
  }

  /// 将最新标注移至重做栈；空栈时无副作用。
  public mutating func undo() {
    if let last = annotations.popLast() { undone.append(last) }
  }

  /// 恢复上次撤销的标注；空栈时无副作用。
  public mutating func redo() {
    if let last = undone.popLast() { annotations.append(last) }
  }

  /// 调整裁剪原点时平移已提交和已撤销的标注，使标注继续锚定原屏幕内容，不改变顺序。
  public mutating func translate(by offset: CGPoint) {
    func shifted(_ annotation: Annotation) -> Annotation {
      var result = annotation
      result.points = result.points.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
      return result
    }
    annotations = annotations.map(shifted)
    undone = undone.map(shifted)
  }
}
