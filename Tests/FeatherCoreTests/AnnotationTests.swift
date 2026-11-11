import Foundation
import Testing

@testable import FeatherCore

struct AnnotationTests {
  private var annotation: Annotation {
    Annotation(
      tool: .arrow, points: [CGPoint(x: 10, y: 20), CGPoint(x: 100, y: 50)],
      color: InkColor.palette[0])
  }

  @Test func undoRedoKeepsOriginalOrder() {
    var history = AnnotationHistory()
    let first = annotation
    let second = annotation
    history.append(first)
    history.append(second)
    history.undo()
    #expect(history.annotations == [first])
    #expect(history.canRedo)
    history.redo()
    #expect(history.annotations == [first, second])
    #expect(!history.canRedo)
  }

  @Test func newStrokeClearsRedoBranch() {
    var history = AnnotationHistory()
    history.append(annotation)
    history.undo()
    let replacement = annotation
    history.append(replacement)
    history.redo()
    #expect(history.annotations == [replacement])
  }

  @Test func boundedHistoryDoesNotSilentlyDropAnnotations() {
    var history = AnnotationHistory()
    for _ in 0..<200 {
      let appended = history.append(annotation)
      #expect(appended)
    }
    let previous = history.annotations
    let overflowAppended = history.append(annotation)
    #expect(!overflowAppended)
    #expect(history.annotations == previous)
    history.undo()
    let appendedAfterUndo = history.append(annotation)
    #expect(appendedAfterUndo)
    #expect(history.annotations.count == 200)
  }

  @Test func emptyHistoryOperationsAreSafe() {
    var history = AnnotationHistory()
    history.undo()
    history.redo()
    #expect(!history.canUndo && !history.canRedo)
    let emptyAppended = history.append(
      Annotation(tool: .pen, points: [], color: InkColor.palette[0]))
    #expect(!emptyAppended)
  }

  @Test func inputsAreBounded() {
    let result = Annotation(
      tool: .text, points: [.zero], color: InkColor(-3, 8, 0.5),
      lineWidth: 0, text: String(repeating: "字", count: 2100))
    #expect(result.lineWidth == 1)
    #expect(result.text.count == 2000)
    #expect(result.color == InkColor(0, 1, 0.5))
  }
}
