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

  @Test func toolOptionsAvoidToolbarAndClampToOffsetScreen() {
    let screen = CGRect(x: 100, y: 50, width: 800, height: 600)
    for toolbar in [
      CGRect(x: 112, y: 62, width: 600, height: 64),
      CGRect(x: 288, y: 574, width: 600, height: 64),
      CGRect(x: 288, y: 400, width: 600, height: 64),
    ] {
      let options = SelectionGeometry.optionsFrame(
        toolbar: toolbar, size: CGSize(width: 380, height: 110), bounds: screen)
      #expect(screen.insetBy(dx: 12, dy: 12).contains(options))
      #expect(options.maxY <= toolbar.minY || options.minY >= toolbar.maxY)
      #expect(options.width == 380 && options.height == 110)
    }
    let narrow = CGRect(x: 0, y: 0, width: 320, height: 500)
    let frame = SelectionGeometry.optionsFrame(
      toolbar: CGRect(x: 12, y: 100, width: 296, height: 64),
      size: CGSize(width: 380, height: 110), bounds: narrow)
    #expect(frame.width == 296)
    #expect(narrow.insetBy(dx: 12, dy: 12).contains(frame))
    let above = SelectionGeometry.optionsFrame(
      toolbar: CGRect(x: 112, y: 300, width: 600, height: 64),
      size: CGSize(width: 360, height: 58), bounds: screen, preferAbove: true)
    #expect(above.maxY == 300)
    let fallback = SelectionGeometry.optionsFrame(
      toolbar: CGRect(x: 112, y: 62, width: 600, height: 64),
      size: CGSize(width: 360, height: 58), bounds: screen, preferAbove: true)
    #expect(fallback.minY == 126)
  }
}
