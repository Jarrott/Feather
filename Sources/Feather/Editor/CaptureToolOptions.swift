import FeatherCore
import SwiftUI

/// 独立属性浮层：选工具才显示颜色和粗细；保存进度与错误共用该位置，不改变主工具条高度。
struct CaptureToolOptions: View {
  @ObservedObject var document: EditorDocument

  /// 返回所需浮层尺寸；移动模式且无状态信息时返回 nil。尺寸包含阴影留白，布局由覆盖层约束。
  @MainActor
  static func preferredSize(for document: EditorDocument) -> CGSize? {
    if document.isExporting { return CGSize(width: 208, height: 58) }
    let hasOptions = !document.isSelectingRegion
    guard hasOptions || document.error != nil else { return nil }
    let width: CGFloat = document.error != nil ? 380 : document.tool == .highlight ? 216 : 360
    return CGSize(
      width: width, height: 16 + (hasOptions ? 42 : 0) + (document.error != nil ? 52 : 0))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if document.isExporting {
        HStack(spacing: 10) {
          ProgressView().controlSize(.small)
          Text(L.text("editor.saving"))
          Spacer()
        }.frame(height: 42)
      } else {
        if !document.isSelectingRegion { options.frame(height: 42) }
        if let error = document.error {
          HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(CaptureStyle.cancel)
            Text(error).lineLimit(2).fixedSize(horizontal: false, vertical: true)
          }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.88))
            .frame(height: 52, alignment: .center)
        }
      }
    }
    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.72))
    .padding(.horizontal, 14)
    .background(CapturePanelBackground())
    .padding(8)
    .environment(\.colorScheme, .dark)
  }

  @ViewBuilder
  private var options: some View {
    if document.tool == .redact {
      HStack(spacing: 10) {
        RoundedRectangle(cornerRadius: 2).fill(.black).frame(width: 18, height: 18)
          .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white.opacity(0.35)))
        Text(L.text("overlay.redactionHint"))
        Spacer()
      }
    } else {
      HStack(spacing: 8) {
        ForEach(Array(InkColor.palette.enumerated()), id: \.offset) { index, color in
          Button {
            document.color = color
          } label: {
            Circle().fill(Color(red: color.red, green: color.green, blue: color.blue))
              .frame(width: 14, height: 14).padding(3)
              .overlay(
                Circle().stroke(.white.opacity(document.color == color ? 0.95 : 0.12), lineWidth: 1)
              )
          }.buttonStyle(.plain).help(L.text("color.\(index)"))
            .accessibilityLabel(L.text("color.\(index)"))
            .accessibilityAddTraits(document.color == color ? .isSelected : [])
        }
        if document.tool != .highlight {
          Rectangle().fill(.white.opacity(0.16)).frame(width: 1, height: 18).padding(.horizontal, 2)
          Slider(value: $document.lineWidth, in: 2...16, step: 1)
            .tint(CaptureStyle.accent).controlSize(.mini).frame(minWidth: 54, maxWidth: .infinity)
            .accessibilityLabel(
              L.text(document.tool == .text ? "overlay.fontSize" : "overlay.lineWidth"))
          Text(
            "\(Int(document.tool == .text ? max(18, document.lineWidth * 5) : document.lineWidth)) px"
          )
          .font(.system(size: 10, design: .monospaced)).monospacedDigit().frame(
            width: 36, alignment: .trailing)
        }
      }
    }
  }
}
