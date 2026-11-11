import FeatherCore
import SwiftUI

extension AnnotationTool {
  var symbol: String {
    switch self {
    case .rectangle: "rectangle"
    case .ellipse: "circle"
    case .arrow: "arrow.up.right"
    case .pen: "pencil"
    case .highlight: "highlighter"
    case .text: "t.square"
    case .redact: "rectangle.lefthalf.filled"
    }
  }
  var title: String { L.text("tool.\(rawValue)") }
}

/// 固定高度的单排截图工具条；标注、历史和输出按组排列，属性由独立浮层承载。
struct CaptureToolbar: View {
  @ObservedObject var document: EditorDocument
  let onCancel: () -> Void
  static let preferredSize = CGSize(width: 600, height: 64)

  var body: some View {
    HStack(spacing: 4) {
      ForEach(Array(AnnotationTool.allCases.enumerated()), id: \.element) { index, tool in
        let selected = !document.isSelectingRegion && document.tool == tool
        CaptureToolButton(
          icon: tool.symbol, title: "\(tool.title) (\(index + 1))",
          hint: selected ? L.text("overlay.deselect") : nil, selected: selected
        ) { document.selectTool(tool, toggleSelection: true) }
      }
      divider
      CaptureToolButton(icon: "arrow.uturn.backward", title: L.text("shortcut.undo") + " (⌘Z)") {
        document.history.undo()
      }.disabled(!document.history.canUndo)
      CaptureToolButton(icon: "arrow.uturn.forward", title: L.text("shortcut.redo") + " (⇧⌘Z)") {
        document.history.redo()
      }.disabled(!document.history.canRedo)
      divider
      CaptureToolButton(icon: "square.and.arrow.down", title: L.text("shortcut.save") + " (⌘S)") {
        document.save(closeAfter: true)
      }.contextMenu {
        Button(L.text("shortcut.saveAs")) { document.save(asNewLocation: true, closeAfter: true) }
      }
      CaptureToolButton(icon: "xmark", title: L.text("overlay.cancel"), tint: CaptureStyle.cancel) {
        onCancel()
      }
      CaptureToolButton(
        icon: "checkmark", title: L.text("editor.done") + " (↩)", tint: CaptureStyle.accent
      ) {
        document.copy(closeAfter: true)
      }
    }
    .disabled(document.isExporting)
    .padding(.horizontal, 8).frame(height: 48)
    .background(CapturePanelBackground())
    .padding(8)
    .environment(\.colorScheme, .dark)
  }

  private var divider: some View {
    Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: 28).padding(.horizontal, 4)
  }
}
