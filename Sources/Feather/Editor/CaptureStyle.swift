import AppKit
import SwiftUI

/// 截图浮层统一的视觉参数，独立于浅色设置界面；不影响导出图像和标注颜色。
@MainActor
enum CaptureStyle {
  static let selectionColor = NSColor(srgbRed: 0.16, green: 0.94, blue: 0.40, alpha: 1)
  static let accent = Color(nsColor: selectionColor)
  static let cancel = Color(red: 1, green: 0.37, blue: 0.39)
}

/// 在冻结截图上使用系统 HUD 材质；仅对小面积工具条混合，不再次读取屏幕。
private struct CaptureMaterial: NSViewRepresentable {
  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.material = .hudWindow
    view.blendingMode = .withinWindow
    view.state = .active
    view.appearance = NSAppearance(named: .darkAqua)
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// 主工具条和属性卡片共用的深色磨砂背景；细描边与阴影分离画面，不响应鼠标。
struct CapturePanelBackground: View {
  var body: some View {
    let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
    CaptureMaterial()
      .overlay(Color(red: 0.09, green: 0.11, blue: 0.12).opacity(0.78))
      .overlay(
        LinearGradient(
          colors: [.white.opacity(0.045), .clear], startPoint: .top, endPoint: .bottom)
      )
      .clipShape(shape)
      .overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
      .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 3)
      .allowsHitTesting(false)
  }
}

/// 统一图标按钮的悬停、选中、按下和禁用状态；每个操作保留名称和键盘提示供辅助功能读取。
struct CaptureToolButton: View {
  let icon: String
  let title: String
  var hint: String?
  var selected = false
  var tint: Color = .white
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .regular))
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .contentShape(Rectangle())
    }
    .buttonStyle(CaptureToolbarButtonStyle(selected: selected, tint: tint))
    .help(hint.map { title + "\n" + $0 } ?? title)
    .accessibilityLabel(title)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct CaptureToolbarButtonStyle: ButtonStyle {
  let selected: Bool
  let tint: Color
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(selected ? CaptureStyle.accent : tint)
      .background(
        selected
          ? CaptureStyle.accent.opacity(0.12) : .white.opacity(isHovered && isEnabled ? 0.10 : 0),
        in: RoundedRectangle(cornerRadius: 5)
      )
      .overlay(alignment: .bottom) {
        if selected {
          Capsule().fill(CaptureStyle.accent).frame(width: 12, height: 2).offset(y: -2)
        }
      }
      .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 0.96) : 0.28)
      .onHover { isHovered = $0 }
      .animation(.easeOut(duration: 0.10), value: isHovered)
  }
}
