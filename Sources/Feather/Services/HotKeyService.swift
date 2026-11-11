import AppKit
import Carbon.HIToolbox

/// 使用系统热键注册 API，不监听全局键盘输入，也不请求辅助功能权限。
@MainActor
final class HotKeyService {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private var registeredShortcut: CaptureShortcut?
  var onTrigger: (() -> Void)?

  /// 安装一次事件处理器；安装失败会由 register 返回错误，退出时显式释放。
  init() {
    var event = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let pointer = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, context in
        guard let context else { return OSStatus(eventNotHandledErr) }
        let service = Unmanaged<HotKeyService>.fromOpaque(context).takeUnretainedValue()
        Task { @MainActor in service.onTrigger?() }
        return noErr
      }, 1, &event, pointer, &handler)
  }

  /// 先注册新组合，再释放旧热键；冲突时保留旧热键并抛出可展示错误。
  func register(_ shortcut: CaptureShortcut) throws {
    guard handler != nil else { throw HotKeyError.unavailable }
    guard registeredShortcut != shortcut else { return }
    var next: EventHotKeyRef?
    let id = EventHotKeyID(signature: 0x4654_4852, id: 1)
    let result = RegisterEventHotKey(
      shortcut.keyCode, shortcut.modifiers, id,
      GetApplicationEventTarget(), 0, &next)
    guard result == noErr, let next else { throw HotKeyError.conflict }
    if let hotKey { UnregisterEventHotKey(hotKey) }
    hotKey = next
    registeredShortcut = shortcut
  }

  /// 应用退出时移除注册和处理器，避免回调引用失效对象。
  func stop() {
    if let hotKey { UnregisterEventHotKey(hotKey) }
    if let handler { RemoveEventHandler(handler) }
    hotKey = nil
    handler = nil
    registeredShortcut = nil
  }
}

enum HotKeyError: LocalizedError {
  case conflict, unavailable
  var errorDescription: String? {
    L.text(self == .conflict ? "shortcut.conflict" : "shortcut.unavailable")
  }
}
