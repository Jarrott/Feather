import AppKit
import Combine

/// 临时录制当前窗口的按键；不监听其他应用，不申请权限。
/// 点击其他位置、离开页面、窗口失焦或 Esc 均取消，旧热键始终保留注册。
@MainActor
final class ShortcutRecorder: ObservableObject {
  @Published private(set) var isRecording = false
  @Published private(set) var modifierPreview = ""
  @Published private(set) var message: String?
  @Published private(set) var hasError = false
  private var monitor: Any?
  private var observers: [NSObjectProtocol] = []
  private weak var model: AppModel?
  private weak var window: NSWindow?

  /// 只在有目标窗口时开启本地事件监听；完成、取消和 onDisappear 必须调用 cancel 清理。
  func start(model: AppModel, window: NSWindow?) {
    guard !isRecording, let window, !model.isRecordingShortcut else { return }
    self.model = model
    self.window = window
    message = nil
    hasError = false
    modifierPreview = ""
    model.error = nil
    model.isRecordingShortcut = true
    isRecording = true
    // Carbon 会先消费已注册热键；通过该回调把按下旧组合视作保留当前设置。
    model.recordExistingShortcut = { [weak self, weak model] in
      guard let model else { return }
      self?.accept(model.shortcut)
    }
    monitor = NSEvent.addLocalMonitorForEvents(matching: [
      .keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown,
    ]) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self else { return false }
        return self.handle(event) == nil
      }
      return consumed ? nil : event
    }
    guard monitor != nil else {
      cancel()
      message = L.text("shortcut.unavailable")
      hasError = true
      return
    }
    for (name, object) in [
      (NSWindow.didResignKeyNotification, window as AnyObject),
      (NSWindow.willCloseNotification, window as AnyObject),
      (NSApplication.didResignActiveNotification, NSApp as AnyObject),
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
          [weak self] _ in
          MainActor.assumeIsolated { self?.cancel() }
        })
    }
  }

  /// 处理应用内输入并在录制时消费按键，避免触发菜单命令；鼠标点击仍正常传递。
  func handle(_ event: NSEvent) -> NSEvent? {
    guard isRecording else { return event }
    if event.type == .leftMouseDown || event.type == .rightMouseDown || event.window !== window {
      cancel()
      return event
    }
    if event.type == .flagsChanged {
      modifierPreview = CaptureShortcut.modifierTitle(
        CaptureShortcut.carbonModifiers(event.modifierFlags))
      return nil
    }
    guard event.type == .keyDown else { return event }
    if event.keyCode == 53 {
      cancel()
      return nil
    }
    guard !event.isARepeat else { return nil }
    do { accept(try CaptureShortcut.recorded(from: event)) } catch {
      message = error.localizedDescription
      hasError = true
    }
    return nil
  }

  /// 仅在系统注册成功后结束录制；冲突保持旧设置并允许继续输入新组合。
  private func accept(_ shortcut: CaptureShortcut) {
    guard isRecording, let model else { return }
    guard model.changeShortcut?(shortcut) == true else {
      message = model.error ?? L.text("shortcut.unavailable")
      hasError = true
      return
    }
    cancel()
    message = L.text("shortcut.saved")
    hasError = false
  }

  /// 幂等清理本地监听和通知观察者；取消绝不修改快捷键或持久化偏好。
  func cancel() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    model?.isRecordingShortcut = false
    model?.recordExistingShortcut = nil
    model = nil
    window = nil
    isRecording = false
    modifierPreview = ""
    message = nil
    hasError = false
  }
}
