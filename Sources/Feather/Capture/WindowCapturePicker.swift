import AppKit
import ScreenCaptureKit
import SwiftUI

/// 用户触发后枚举窗口并选择；只展示系统标题，不做缩略图预取，不记录窗口内容。
@MainActor
final class WindowCapturePicker: NSObject, NSWindowDelegate {
  private var panel: NSPanel?
  private var continuation: CheckedContinuation<CGWindowID?, Never>?

  func focus() { panel?.makeKeyAndOrderFront(nil) }

  /// 可取消的原生选择面板；关闭和选择均只恢复一次调用方。
  func select(from windows: [SCWindow]) async -> CGWindowID? {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      let panel = NSPanel(
        contentRect: CGRect(x: 0, y: 0, width: 520, height: 420),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      panel.title = L.text("capture.window")
      panel.isReleasedWhenClosed = false
      panel.delegate = self
      panel.contentView = NSHostingView(
        rootView: WindowPickerView(windows: windows) { [weak self] in self?.finish($0) })
      self.panel = panel
      panel.center()
      NSApp.activate(ignoringOtherApps: true)
      panel.makeKeyAndOrderFront(nil)
    }
  }

  func windowWillClose(_ notification: Notification) { finish(nil) }

  private func finish(_ window: SCWindow?) {
    let reply = continuation
    continuation = nil
    panel?.delegate = nil
    panel?.close()
    panel = nil
    reply?.resume(returning: window?.windowID)
  }
}

private struct WindowPickerView: View {
  let windows: [SCWindow]
  let onSelect: (SCWindow?) -> Void
  var body: some View {
    VStack(spacing: 12) {
      if windows.isEmpty {
        Text(L.text("capture.noWindows")).frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(windows, id: \.windowID) { window in
          Button {
            onSelect(window)
          } label: {
            VStack(alignment: .leading, spacing: 4) {
              Text(window.owningApplication?.applicationName ?? L.text("capture.window")).font(
                .headline)
              Text(window.title ?? L.text("capture.untitledWindow")).lineLimit(2).foregroundStyle(
                .secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
          }.buttonStyle(.plain)
        }
      }
      HStack {
        Spacer()
        Button(L.text("cancel")) { onSelect(nil) }.keyboardShortcut(.cancelAction)
      }
    }.padding(16)
  }
}
