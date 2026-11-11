import Foundation
import Testing

@testable import FeatherCore

struct SelectionGeometryTests {
  private let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)

  @Test func movingKeepsSizeAndClampsBothEdges() {
    let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(
      SelectionGeometry.move(rect, by: CGPoint(x: -500, y: 800), inside: bounds)
        == CGRect(x: 0, y: 400, width: 300, height: 200))
  }

  @Test func resizingFixesOppositeEdgesAndPreventsFlipping() {
    let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(
      SelectionGeometry.resize(rect, handle: .topLeft, by: CGPoint(x: 500, y: 500), inside: bounds)
        == CGRect(x: 396, y: 296, width: 4, height: 4))
    #expect(
      SelectionGeometry.resize(
        rect, handle: .bottomRight, by: CGPoint(x: 700, y: 700), inside: bounds)
        == CGRect(x: 100, y: 100, width: 700, height: 500))
  }

  @Test func middleHandleChangesOnlyOneAxis() {
    let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
    #expect(
      SelectionGeometry.resize(rect, handle: .left, by: CGPoint(x: 20, y: 70), inside: bounds)
        == CGRect(x: 120, y: 100, width: 280, height: 200))
    #expect(Set(SelectionHandle.allCases.map { $0.point(in: rect).debugDescription }).count == 8)
  }

  @Test func toolbarStaysOnScreenForEdgeAndFullscreenSelections() {
    for selection in [
      CGRect(x: 10, y: 10, width: 80, height: 80),
      CGRect(x: 720, y: 500, width: 80, height: 100), bounds,
    ] {
      let frame = SelectionGeometry.toolbarFrame(
        selection: selection, size: CGSize(width: 620, height: 92), bounds: bounds)
      #expect(bounds.contains(frame))
    }
    let bottom = SelectionGeometry.toolbarFrame(
      selection: CGRect(x: 50, y: 500, width: 200, height: 80),
      size: CGSize(width: 620, height: 92), bounds: bounds)
    #expect(bottom.maxY < 500)
  }

  @Test func changingCropOriginPreservesUndoAndRedoAnchors() {
    var history = AnnotationHistory()
    let annotation = Annotation(
      tool: .arrow, points: [CGPoint(x: 50, y: 40), CGPoint(x: 80, y: 60)],
      color: InkColor.palette[0])
    history.append(annotation)
    history.undo()
    history.translate(by: CGPoint(x: -20, y: -10))
    history.redo()
    #expect(history.annotations[0].id == annotation.id)
    #expect(history.annotations[0].points == [CGPoint(x: 30, y: 30), CGPoint(x: 60, y: 50)])
  }
}
