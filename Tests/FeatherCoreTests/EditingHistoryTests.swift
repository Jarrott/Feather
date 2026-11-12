import CoreGraphics
import Foundation
import Testing

@testable import FeatherCore

struct EditingHistoryTests {
  @Test func cropDeleteTextAndMovesUndoInOrder() throws {
    var history = AnnotationHistory()
    let initialCrop = CGRect(x: 100, y: 80, width: 400, height: 300)
    history.previewCrop(initialCrop)
    let first = Annotation(
      tool: .rectangle, points: [.zero, CGPoint(x: 40, y: 50)], color: .palette[0])
    let text = Annotation(
      tool: .text, points: [CGPoint(x: 70, y: 60)], color: .palette[1], text: "中文", fontSize: 32)
    history.append(first)
    history.append(text)
    let crop = CGRect(x: 120, y: 100, width: 300, height: 200)
    history.previewCrop(crop)
    history.commitCrop(from: initialCrop)
    let shiftedText = try #require(history.annotations.last)
    history.remove(id: first.id)
    var edited = shiftedText
    edited.text = "第二行\nUpdated"
    edited.fontSize = 52
    history.replace(edited)
    history.undo()
    #expect(history.annotations == [shiftedText])
    history.undo()
    #expect(history.annotations.map(\.id) == [first.id, text.id])
    history.undo()
    #expect(history.cropRect == initialCrop && history.annotations == [first, text])
    history.redo()
    history.redo()
    history.redo()
    #expect(history.cropRect == crop && history.annotations == [edited])
  }

  @Test func cropUndoPreservesRedoBranchCoordinates() {
    var history = AnnotationHistory()
    let initial = CGRect(x: 0, y: 0, width: 100, height: 100)
    history.previewCrop(initial)
    let original = Annotation(tool: .pen, points: [CGPoint(x: 40, y: 40)], color: .palette[0])
    history.append(original)
    history.move(id: original.id, by: CGPoint(x: 10, y: 10))
    history.previewCrop(CGRect(x: 20, y: 20, width: 80, height: 80))
    history.commitCrop(from: initial)
    history.undo()
    history.undo()
    history.undo()
    #expect(history.annotations.isEmpty)
    history.redo()
    history.redo()
    history.redo()
    #expect(history.annotations.first?.points.first == CGPoint(x: 30, y: 30))
  }

  @Test func filenameRejectsPathsUnknownTokensAndHandlesCollisions() throws {
    for input in ["../secret", "a/b", "a:b", "a\\b", ".hidden", "{unknown}", "{date", "", "a\nb"] {
      #expect(throws: ExportError.self) { try FilenameTemplate.validated(input) }
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let data = Data([137, 80, 78, 71, 13, 10, 26, 10])
    let first = try PNGExporter.save(
      data, to: root, template: "截图_{width}x{height}", imageSize: CGSize(width: 6000, height: 3000))
    let second = try PNGExporter.save(
      data, to: root, template: "截图_{width}x{height}", imageSize: CGSize(width: 6000, height: 3000))
    #expect(first.lastPathComponent == "截图_6000x3000.png")
    #expect(second.lastPathComponent == "截图_6000x3000-1.png")
    #expect(try Data(contentsOf: first) == data)
  }

  @Test func repeatedPixelLogicalRoundTripDoesNotGrowCrop() throws {
    let image = CGSize(width: 800, height: 600)
    let screen = CGSize(width: 2056, height: 1329)
    var crop = CGRect(x: 200, y: 150, width: 400, height: 300)
    for _ in 0..<100 {
      let logical = CGRect(
        x: crop.minX * screen.width / image.width,
        y: crop.minY * screen.height / image.height,
        width: crop.width * screen.width / image.width,
        height: crop.height * screen.height / image.height)
      crop = try #require(
        CaptureGeometry.pixelRect(selection: logical, viewSize: screen, imageSize: image))
    }
    #expect(crop == CGRect(x: 200, y: 150, width: 400, height: 300))
  }

  @Test func shortcutMappingRemainsExplicit() {
    #expect(AnnotationTool.forShortcut("7") == .redact)
    #expect(AnnotationTool.forShortcut("8") == .mosaic)
    #expect(AnnotationTool.forShortcut("0") == nil)
    #expect(Set(AnnotationTool.allCases.map(\.shortcut)).count == AnnotationTool.allCases.count)
  }
}
