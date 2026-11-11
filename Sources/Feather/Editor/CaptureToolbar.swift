import AppKit
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
    case .redact: "square.fill"
    }
  }
  var title: String { L.text("tool.\(rawValue)") }
}

/// 贴近选区的紧凑工具条；只展示已实现的标注和输出功能，不创建独立编辑窗口。
struct CaptureToolbar: View {
  @ObservedObject var document: EditorDocument
  let onCancel: () -> Void

  /// 框选时仅显示一排操作；选择标注工具或导出时展开选项行，错误额外占两行文本空间。
  @MainActor
  static func height(for document: EditorDocument) -> CGFloat {
    let optionsHeight: CGFloat = !document.isSelectingRegion || document.isExporting ? 32 : 0
    return 52 + optionsHeight + (document.error == nil ? 0 : 33)
  }

  var body: some View {
    VStack(spacing: 9) {
      HStack(spacing: 5) {
        toolButton(
          "cursorarrow", title: L.text("overlay.move"), selected: document.isSelectingRegion
        ) {
          document.isSelectingRegion = true
        }
        ForEach(Array(AnnotationTool.allCases.enumerated()), id: \.element) { index, tool in
          toolButton(
            tool.symbol, title: "\(tool.title) (\(index + 1))",
            selected: !document.isSelectingRegion && document.tool == tool
          ) {
            document.tool = tool
            document.isSelectingRegion = false
          }
        }
        separator
        toolButton("arrow.uturn.backward", title: L.text("shortcut.undo")) {
          document.history.undo()
        }
        .disabled(!document.history.canUndo)
        toolButton("arrow.uturn.forward", title: L.text("shortcut.redo")) {
          document.history.redo()
        }
        .disabled(!document.history.canRedo)
        separator
        toolButton("square.and.arrow.down", title: L.text("shortcut.save")) {
          document.save(closeAfter: true)
        }
        .contextMenu {
          Button(L.text("shortcut.saveAs")) { document.save(asNewLocation: true, closeAfter: true) }
        }
        toolButton("xmark", title: L.text("overlay.cancel"), tint: .red) { onCancel() }
        toolButton("checkmark", title: L.text("editor.done"), tint: Theme.mint) {
          document.copy(closeAfter: true)
        }
      }.disabled(document.isExporting)
      if !document.isSelectingRegion || document.isExporting {
        HStack(spacing: 10) {
          if document.isExporting {
            ProgressView().controlSize(.mini)
            Text(L.text("editor.saving"))
          } else {
            if document.tool != .redact {
              ForEach(Array(InkColor.palette.enumerated()), id: \.offset) { index, color in
                Button {
                  document.color = color
                } label: {
                  Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
                    .frame(width: 16, height: 16).padding(3)
                    .overlay(
                      Circle().stroke(document.color == color ? Color.white : .clear, lineWidth: 1))
                }.buttonStyle(.plain).help(L.text("color.\(index)"))
              }
            }
            if document.tool != .redact && document.tool != .highlight {
              Slider(value: $document.lineWidth, in: 2...16, step: 1).frame(width: 85).controlSize(
                .mini)
              Text("\(Int(document.lineWidth)) px").monospacedDigit()
            }
            Spacer(minLength: 0)
            Text(document.tool.title)
          }
          Spacer(minLength: 0)
          Text("⌘S · ↩ · Esc").font(.system(size: 10, design: .monospaced))
        }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.65)).frame(height: 23)
          .disabled(document.isExporting)
      }
      if let error = document.error {
        Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
          .foregroundStyle(Color(red: 1, green: 0.65, blue: 0.6)).lineLimit(2)
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      Color(red: 0.10, green: 0.15, blue: 0.14).opacity(0.98),
      in: RoundedRectangle(cornerRadius: 11)
    )
    .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.12)))
    .environment(\.colorScheme, .dark)
  }

  private var separator: some View {
    Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 24).padding(.horizontal, 4)
  }

  private func toolButton(
    _ icon: String, title: String, selected: Bool = false,
    tint: Color = .white, action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: icon).font(.system(size: 17, weight: .medium))
        .foregroundStyle(selected ? Theme.mint : tint)
        .frame(width: 32, height: 32)
        .background(selected ? .white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }.buttonStyle(.plain).help(title).accessibilityLabel(title)
  }
}
