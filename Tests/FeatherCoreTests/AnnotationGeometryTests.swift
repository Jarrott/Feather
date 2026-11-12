import AppKit
import Testing

@testable import FeatherCore

@MainActor
struct AnnotationGeometryTests {
  @Test func hollowShapesHitOnlyTheirOutline() {
    for tool in [AnnotationTool.rectangle, .ellipse] {
      let annotation = Annotation(
        tool: tool, points: [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 80)],
        color: InkColor.palette[0])
      #expect(AnnotationGeometry.contains(CGPoint(x: 20, y: 50), in: annotation, tolerance: 6))
      #expect(!AnnotationGeometry.contains(CGPoint(x: 60, y: 50), in: annotation, tolerance: 6))
      #expect(!AnnotationGeometry.contains(CGPoint(x: 5, y: 50), in: annotation, tolerance: 6))
    }
  }

  @Test func penBoundsIncludeIntermediatePointsAndDotsCanBeSelected() {
    let pen = Annotation(
      tool: .pen, points: [.zero, CGPoint(x: 100, y: 80), CGPoint(x: 20, y: 10)],
      color: InkColor.palette[0])
    #expect(AnnotationGeometry.bounds(of: pen) == CGRect(x: 0, y: 0, width: 100, height: 80))
    #expect(AnnotationGeometry.contains(CGPoint(x: 100, y: 80), in: pen, tolerance: 3))
    let dot = Annotation(tool: .pen, points: [CGPoint(x: 50, y: 40)], color: InkColor.palette[0])
    #expect(AnnotationGeometry.contains(CGPoint(x: 52, y: 40), in: dot, tolerance: 3))
  }

  @Test func filledRegionsTextAndArrowheadsAreSelectable() {
    for tool in [AnnotationTool.highlight, .redact] {
      let annotation = Annotation(
        tool: tool, points: [.zero, CGPoint(x: 80, y: 40)], color: InkColor.palette[0])
      #expect(AnnotationGeometry.contains(CGPoint(x: 40, y: 20), in: annotation, tolerance: 3))
    }
    let text = Annotation(tool: .text, points: [.zero], color: InkColor.palette[0], text: "标注")
    #expect(AnnotationGeometry.bounds(of: text).width > 20)
    #expect(AnnotationGeometry.contains(CGPoint(x: 5, y: 5), in: text, tolerance: 3))
    let arrow = Annotation(
      tool: .arrow, points: [.zero, CGPoint(x: 100, y: 0)], color: InkColor.palette[0], lineWidth: 8
    )
    #expect(AnnotationGeometry.contains(CGPoint(x: 78, y: 8), in: arrow, tolerance: 0))
  }

  @Test func draggingClampsToImageAndCanBringCroppedObjectsBackInside() {
    let box = Annotation(
      tool: .rectangle, points: [CGPoint(x: 20, y: 30), CGPoint(x: 80, y: 90)],
      color: InkColor.palette[0])
    let image = CGRect(x: 0, y: 0, width: 200, height: 150)
    #expect(
      AnnotationGeometry.constrainedOffset(CGPoint(x: -500, y: 500), for: box, inside: image)
        == CGPoint(x: -20, y: 60))
    let cropped = box.translated(by: CGPoint(x: -40, y: 0))
    #expect(
      AnnotationGeometry.constrainedOffset(CGPoint(x: -10, y: 0), for: cropped, inside: image).x
        == 0)
    #expect(
      AnnotationGeometry.constrainedOffset(CGPoint(x: 30, y: 0), for: cropped, inside: image).x
        == 30)
  }
}
