import AppKit
import Carbon.HIToolbox

/// 全局截图快捷键；以物理键码和 Carbon 修饰键标识，显示名称取自录制时的键盘布局。
/// Codable 解码也执行校验，旧版预设通过 legacyPreset 兼容读取。
struct CaptureShortcut: Codable, Hashable {
  let keyCode: UInt32
  let modifiers: UInt32
  let keyLabel: String

  static let commandShift2 = CaptureShortcut(
    keyCode: 19, modifiers: UInt32(cmdKey | shiftKey), keyLabel: "2")
  static let commandOptionA = CaptureShortcut(
    keyCode: 0, modifiers: UInt32(cmdKey | optionKey), keyLabel: "A")
  static let controlOptionS = CaptureShortcut(
    keyCode: 1, modifiers: UInt32(controlKey | optionKey), keyLabel: "S")
  static let presets: [CaptureShortcut] = [.commandShift2, .commandOptionA, .controlOptionS]
  private static let allowedModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)
  private static let functionKeys: [UInt32: String] = [
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
    101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
    106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
  ]
  private static let specialKeys: [UInt32: String] = [
    36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 71: "Clear", 76: "⌤",
    115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
  ]

  private init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.keyLabel = keyLabel
  }

  var title: String { Self.modifierTitle(modifiers) + keyLabel }

  /// 仅接收字母/数字/符号与受支持的特殊键；普通键必须包含 ⌘、⌥ 或 ⌃，F1–F20 可单独使用。
  /// 拒绝应用自身编辑命令和常见系统保留组合；无副作用，失败返回本地化原因。
  static func validated(keyCode: UInt32, modifiers: UInt32, keyLabel: String) throws
    -> CaptureShortcut
  {
    guard keyCode <= 126, keyCode != UInt32(kVK_Escape), !(54...63).contains(keyCode),
      modifiers & ~allowedModifiers == 0
    else { throw ShortcutValidationError.unsupported }
    guard modifiers & UInt32(cmdKey | optionKey | controlKey) != 0 || functionKeys[keyCode] != nil
    else { throw ShortcutValidationError.needsModifier }
    let label: String
    if let special = functionKeys[keyCode] ?? specialKeys[keyCode] {
      label = special
    } else {
      guard keyLabel.count == 1,
        keyLabel.unicodeScalars.allSatisfy({
          !CharacterSet.controlCharacters.contains($0)
            && !CharacterSet.whitespacesAndNewlines.contains($0)
        })
      else { throw ShortcutValidationError.unsupported }
      let uppercase = keyLabel.uppercased()
      label = uppercase.count == 1 ? uppercase : keyLabel
    }
    // 单独 Command 的常见编辑/窗口命令，以及本应用的另存为与重做不可被全局截图占用。
    let commandOnlyReserved: Set<UInt32> = [
      0, 6, 7, 8, 9, 12, 13, 31, 35, 43, 45, 46, 48, 49, 1, 4,
    ]
    if (modifiers == UInt32(cmdKey) && commandOnlyReserved.contains(keyCode))
      || (modifiers == UInt32(cmdKey | shiftKey) && [UInt32(1), 6].contains(keyCode))
      || (modifiers == UInt32(controlKey) && keyCode == 49)
      || (modifiers == UInt32(cmdKey | optionKey) && keyCode == 49)
    {
      throw ShortcutValidationError.reserved
    }
    return CaptureShortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label)
  }

  /// 从应用窗口收到的按键事件取键码和名称，忽略 Caps Lock/Fn 等非热键修饰状态。
  @MainActor
  static func recorded(from event: NSEvent) throws -> CaptureShortcut {
    try validated(
      keyCode: UInt32(event.keyCode), modifiers: carbonModifiers(event.modifierFlags),
      keyLabel: event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
    )
  }

  static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var value: UInt32 = 0
    if flags.contains(.command) { value |= UInt32(cmdKey) }
    if flags.contains(.shift) { value |= UInt32(shiftKey) }
    if flags.contains(.option) { value |= UInt32(optionKey) }
    if flags.contains(.control) { value |= UInt32(controlKey) }
    return value
  }

  static func modifierTitle(_ modifiers: UInt32) -> String {
    [
      (UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"),
      (UInt32(cmdKey), "⌘"),
    ]
    .filter { modifiers & $0.0 != 0 }.map { $0.1 + " " }.joined()
  }

  static func legacyPreset(named name: String?) -> CaptureShortcut? {
    switch name {
    case "commandShift2": .commandShift2
    case "commandOptionA": .commandOptionA
    case "controlOptionS": .controlOptionS
    default: nil
    }
  }

  private enum CodingKeys: String, CodingKey { case keyCode, modifiers, keyLabel }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    self = try Self.validated(
      keyCode: values.decode(UInt32.self, forKey: .keyCode),
      modifiers: values.decode(UInt32.self, forKey: .modifiers),
      keyLabel: values.decode(String.self, forKey: .keyLabel))
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(keyCode)
    hasher.combine(modifiers)
  }
}

enum ShortcutValidationError: LocalizedError {
  case needsModifier, reserved, unsupported

  var errorDescription: String? {
    switch self {
    case .needsModifier: L.text("shortcut.needsModifier")
    case .reserved: L.text("shortcut.reserved")
    case .unsupported: L.text("shortcut.unsupported")
    }
  }
}
