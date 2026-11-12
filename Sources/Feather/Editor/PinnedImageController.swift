import AppKit
import FeatherCore
import SwiftUI

/// 有界的内存贴图窗口；退出应用释放图片，最多八张，不在后台创建截图或历史文件。
@MainActor
final class PinnedImageController: NSObject, NSWindowDelegate {
  private(set) var windows: [NSWindow] = []
  private let displaysWindows: Bool

  /// 默认显示真实贴图；测试可关闭窗口展示，仍验证相同的面板配置和生命周期。
  init(displaysWindows: Bool = true) {
    self.displaysWindows = displaysWindows
    super.init()
  }

  /// 从已经合成的图像创建可拖动贴图；达到上限返回 false，保留原编辑会话。
  func pin(_ image: CGImage, model: AppModel) -> Bool {
    guard windows.count < 8, let screen = NSScreen.main ?? NSScreen.screens.first else {
      return false
    }
    let scale = min(
      1 / screen.backingScaleFactor,
      min(
        screen.visibleFrame.width * 0.65 / CGFloat(image.width),
        screen.visibleFrame.height * 0.65 / CGFloat(image.height)))
    let size = CGSize(
      width: max(240, CGFloat(image.width) * scale), height: max(160, CGFloat(image.height) * scale)
    )
    let window = PinnedWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = L.text("editor.pin")
    window.level = .floating
    // NSPanel 默认在应用失去前台时隐藏；贴图需要在切换到其他应用后继续可见。
    window.hidesOnDeactivate = false
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isReleasedWhenClosed = false
    window.isMovableByWindowBackground = true
    window.minSize = CGSize(width: 240, height: 160)
    window.delegate = self
    let document = EditorDocument(image: image, appModel: model)
    window.document = document
    window.contentView = NSHostingView(rootView: PinnedImageView(image: image, document: document))
    window.center()
    windows.append(window)
    if displaysWindows { window.makeKeyAndOrderFront(nil) }
    return true
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    (sender as? PinnedWindow)?.document?.isExporting != true
  }
  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    windows.removeAll { $0 === window }
  }
  var isExporting: Bool {
    windows.contains { ($0 as? PinnedWindow)?.document?.isExporting == true }
  }
}

private final class PinnedWindow: NSPanel {
  var document: EditorDocument?
  override func cancelOperation(_ sender: Any?) {
    if document?.isExporting != true { performClose(sender) }
  }
}

private struct PinnedImageView: View {
  let image: CGImage
  @ObservedObject var document: EditorDocument
  var body: some View {
    VStack(spacing: 0) {
      Image(decorative: image, scale: 1).resizable().interpolation(.none).scaledToFit()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(L.text("editor.pin"))
      HStack {
        Button(L.text("editor.copy")) { document.copy() }.keyboardShortcut("c")
        Button(L.text("editor.save")) { document.save() }.keyboardShortcut("s")
        Spacer()
        if document.isExporting { ProgressView().controlSize(.small) }
      }.disabled(document.isExporting).padding(8)
      if let message = document.error ?? document.status { Text(message).font(.caption).padding(8) }
    }.background(.black.opacity(0.9))
  }
}
