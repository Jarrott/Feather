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

  @Test func removalRestoresOriginalLayerOrderOnUndo() {
    var history = AnnotationHistory()
    let first = annotation
    let second = annotation
    let third = annotation
    for item in [first, second, third] { history.append(item) }
    let removed = history.remove(id: second.id)
    #expect(removed && history.annotations == [first, third])
    let removedAgain = history.remove(id: second.id)
    #expect(!removedAgain)
    history.undo()
    #expect(history.annotations == [first, second, third])
    history.redo()
    #expect(history.annotations == [first, third])
  }

  @Test func removalFollowsCropTranslation() {
    var history = AnnotationHistory()
    let item = annotation
    history.append(item)
    history.remove(id: item.id)
    history.translate(by: CGPoint(x: 5, y: -10))
    history.undo()
    #expect(history.annotations.first?.points == [CGPoint(x: 15, y: 10), CGPoint(x: 105, y: 40)])
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
  @Test func movementHistoryPreservesIdentityOrderAndCropCoordinates() {
    var history = AnnotationHistory()
    let first = annotation
    let second = annotation
    history.append(first)
    history.append(second)
    let moved = history.move(id: first.id, by: CGPoint(x: 30, y: 40))
    #expect(moved)
    #expect(history.annotations.map(\.id) == [first.id, second.id])
    history.undo()
    #expect(history.annotations == [first, second])
    history.translate(by: CGPoint(x: -5, y: -10))
    history.redo()
    #expect(history.annotations[0].points[0] == CGPoint(x: 35, y: 50))
    history.undo()
    history.undo()
    #expect(history.annotations == [first.translated(by: CGPoint(x: -5, y: -10))])
    history.redo()
    history.redo()
    #expect(history.annotations[0].points[0] == CGPoint(x: 35, y: 50))
  }

  @Test func invalidMovesKeepRedoAndNewMoveClearsIt() {
    var history = AnnotationHistory()
    let item = annotation
    history.append(item)
    history.move(id: item.id, by: CGPoint(x: 10, y: 0))
    history.undo()
    let zeroMove = history.move(id: item.id, by: .zero)
    let missingMove = history.move(id: UUID(), by: CGPoint(x: 3, y: 0))
    let invalidMove = history.move(id: item.id, by: CGPoint(x: CGFloat.infinity, y: 0))
    #expect(!zeroMove && !missingMove && !invalidMove)
    #expect(history.canRedo)
    history.move(id: item.id, by: CGPoint(x: 5, y: 0))
    #expect(!history.canRedo)
  }

  @Test func repeatedMovesHaveBoundedUndoWithoutDroppingAnnotations() {
    var history = AnnotationHistory()
    let item = annotation
    history.append(item)
    for _ in 0..<250 { history.move(id: item.id, by: CGPoint(x: 1, y: 0)) }
    for _ in 0..<200 { history.undo() }
    #expect(!history.canUndo)
    #expect(history.annotations.count == 1)
    #expect(history.annotations[0].points[0].x == item.points[0].x + 50)
  }

}
