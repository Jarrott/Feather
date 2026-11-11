import AppKit
import SwiftUI

/// 仅常驻菜单栏；左键截图、右键设置，截图与标注共用一次覆盖层会话。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
  let model = AppModel()
  private let hotKeys = HotKeyService()
  private var statusItem: NSStatusItem?
  private let statusMenu = NSMenu()
  private var settingsWindow: NSWindow?
  private var coordinator: CaptureCoordinator?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    buildMainMenu()
    buildStatusItem()
    model.changeShortcut = { [weak self] shortcut in self?.setShortcut(shortcut) ?? false }
    hotKeys.onTrigger = { [weak self] in
      guard let self else { return }
      if self.model.isRecordingShortcut {
        self.model.recordExistingShortcut?()
      } else {
        self.beginCapture()
      }
    }
    setShortcut(model.shortcut)
  }

  func applicationDidBecomeActive(_ notification: Notification) {
    model.permissionGranted = CGPreflightScreenCaptureAccess()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    coordinator?.isExporting == true ? .terminateCancel : .terminateNow
  }
  func applicationWillTerminate(_ notification: Notification) {
    hotKeys.stop()
    coordinator?.cancel()
  }

  /// 仅显式打开设置时创建窗口；关闭后释放，由 SwiftUI onDisappear 清理录制监听。
  @objc private func showSettings() {
    guard coordinator == nil else {
      coordinator?.focus()
      return
    }
    if settingsWindow == nil {
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
        styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
      window.title = L.text("nav.settings")
      window.isReleasedWhenClosed = false
      window.delegate = self
      window.contentView = NSHostingView(rootView: PreferencesView(model: model))
      window.center()
      settingsWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
    Task { @MainActor [weak self, weak window] in
      guard self?.settingsWindow === window else { return }
      window?.contentView = nil
      self?.settingsWindow = nil
    }
  }

  @objc private func statusItemClicked(_ sender: Any?) {
    guard let event = NSApp.currentEvent, let button = statusItem?.button else { return }
    if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
      NSMenu.popUpContextMenu(statusMenu, with: event, for: button)
    } else {
      beginCapture()
    }
  }

  func menuWillOpen(_ menu: NSMenu) {
    menu.items.first(where: { $0.action == #selector(showSettings) })?.isEnabled =
      coordinator == nil
  }

  /// 用户主动截图时直接尝试 ScreenCaptureKit，由系统验证授权；重复触发聚焦现有选区。
  /// 不使用可能滞后的预检查拦截请求，实际授权拒绝和普通捕捉错误分开处理。
  @objc private func beginCapture() {
    guard !model.isRecordingShortcut else { return }
    if let coordinator {
      coordinator.focus()
      return
    }
    model.error = nil
    settingsWindow?.close()
    let capture = CaptureCoordinator(model: model)
    coordinator = capture
    model.isCapturing = true
    capture.onComplete = { [weak self] in
      self?.model.isCapturing = false
      self?.coordinator = nil
    }
    capture.onError = { [weak self] error in
      guard let self else { return }
      if ScreenCaptureService.isPermissionDenied(error) {
        self.showPermissionRecovery()
        return
      }
      self.model.error = error.localizedDescription
      let alert = NSAlert()
      alert.messageText = L.text("capture.failed")
      alert.informativeText = error.localizedDescription
      alert.runModal()
    }
    capture.start()
  }

  /// 仅在系统实际拒绝后提供设置和当前应用定位入口；授权与重启必须由用户完成。
  /// 展示真实 bundle 路径，帮助区分旧副本/新签名，不循环请求权限或自动修改 TCC。
  private func showPermissionRecovery() {
    NSApp.activate(ignoringOtherApps: true)
    model.status = L.text("permission.retry")
    let alert = NSAlert()
    alert.messageText = L.text("permission.title")
    alert.informativeText = L.format("permission.body", Bundle.main.bundleURL.path)
    alert.addButton(withTitle: L.text("permission.settings"))
    alert.addButton(withTitle: L.text("permission.reveal"))
    alert.addButton(withTitle: L.text("cancel"))
    switch alert.runModal() {
    case .alertFirstButtonReturn: model.openPrivacySettings()
    case .alertSecondButtonReturn:
      NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    default: break
    }
  }

  /// 先注册再持久化；重复组合由系统服务幂等处理，新的显示名称仍可更新。
  @discardableResult
  private func setShortcut(_ shortcut: CaptureShortcut) -> Bool {
    guard model.registerShortcut(shortcut, using: hotKeys.register) else { return false }
    statusMenu.items.first?.title = "\(L.text("capture.start"))    \(shortcut.title)"
    return true
  }

  private func buildStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    item.button?.image = NSImage(
      systemSymbolName: "viewfinder", accessibilityDescription: L.text("app.name"))
    item.button?.toolTip = L.text("menu.tooltip")
    item.button?.target = self
    item.button?.action = #selector(statusItemClicked(_:))
    item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    statusMenu.autoenablesItems = false
    statusMenu.delegate = self
    statusMenu.addItem(
      withTitle: L.text("capture.start"), action: #selector(beginCapture), keyEquivalent: "")
    statusMenu.addItem(
      withTitle: L.text("nav.settings"), action: #selector(showSettings), keyEquivalent: "")
    statusMenu.addItem(.separator())
    statusMenu.addItem(
      withTitle: L.text("menu.quit"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    for entry in statusMenu.items where entry.action != #selector(NSApplication.terminate(_:)) {
      entry.target = self
    }
    statusItem = item
  }

  /// 保留 macOS 标准文本命令，保证文字标注对话框支持剪切、粘贴和全选。
  private func buildMainMenu() {
    let menu = NSMenu()
    let appItem = NSMenuItem()
    let appMenu = NSMenu()
    let preferences = appMenu.addItem(
      withTitle: L.text("nav.settings"), action: #selector(showSettings), keyEquivalent: ",")
    preferences.target = self
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: L.text("menu.quit"), action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    appItem.submenu = appMenu
    menu.addItem(appItem)
    let editItem = NSMenuItem()
    editItem.title = L.text("menu.edit")
    let edit = NSMenu(title: editItem.title)
    edit.addItem(
      withTitle: L.text("edit.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(
      withTitle: L.text("edit.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(
      withTitle: L.text("edit.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: L.text("edit.selectAll"), action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a")
    editItem.submenu = edit
    menu.addItem(editItem)
    NSApp.mainMenu = menu
  }
}
