import AppKit
import Carbon.HIToolbox
import Testing

@testable import Feather

/// 只创建本地事件对象并直接测试处理函数，不向系统注入按键，也不注册真实全局热键。
@MainActor
@Suite(.serialized)
struct ShortcutTests {
  @Test func customCombinationRoundTripsAndUsesModifierOrder() throws {
    let shortcut = try CaptureShortcut.validated(
      keyCode: 0, modifiers: UInt32(controlKey | shiftKey), keyLabel: "a")
    #expect(shortcut.title == "⌃ ⇧ A")
    let decoded = try JSONDecoder().decode(
      CaptureShortcut.self, from: JSONEncoder().encode(shortcut))
    #expect(decoded == shortcut)
    #expect(decoded.keyLabel == "A")
  }

  @Test func plainLettersAndUnsupportedModifiersAreRejected() {
    #expect(throws: ShortcutValidationError.self) {
      try CaptureShortcut.validated(keyCode: 0, modifiers: 0, keyLabel: "a")
    }
    #expect(throws: ShortcutValidationError.self) {
      try CaptureShortcut.validated(keyCode: 0, modifiers: UInt32(shiftKey), keyLabel: "A")
    }
    #expect(throws: ShortcutValidationError.self) {
      try CaptureShortcut.validated(
        keyCode: 0, modifiers: UInt32(cmdKey | alphaLock), keyLabel: "A")
    }
    #expect(throws: ShortcutValidationError.self) {
      try CaptureShortcut.validated(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "⌘")
    }
    #expect(throws: ShortcutValidationError.self) {
      try CaptureShortcut.validated(keyCode: 200, modifiers: UInt32(cmdKey), keyLabel: "A")
    }
  }

  @Test func functionAndArrowKeysUseCanonicalNames() throws {
    let function = try CaptureShortcut.validated(keyCode: 122, modifiers: 0, keyLabel: "")
    #expect(function.title == "F1")
    let arrow = try CaptureShortcut.validated(
      keyCode: 123, modifiers: UInt32(controlKey | optionKey), keyLabel: "")
    #expect(arrow.title == "⌃ ⌥ ←")
  }

  @Test func commonEditingCommandsCannotBecomeCaptureShortcuts() {
    for (keyCode, modifiers) in [
      (UInt32(12), UInt32(cmdKey)), (8, UInt32(cmdKey)),
      (1, UInt32(cmdKey | shiftKey)), (6, UInt32(cmdKey | shiftKey)),
      (49, UInt32(cmdKey)),
    ] {
      #expect(throws: ShortcutValidationError.self) {
        try CaptureShortcut.validated(keyCode: keyCode, modifiers: modifiers, keyLabel: "A")
      }
    }
  }

  @Test func legacyPreferencesMigrateAndMalformedCustomSettingsFallBack() throws {
    try withModel { defaults, model in
      #expect(model.shortcut == .commandShift2)
      defaults.set("commandOptionA", forKey: "shortcut")
      #expect(AppModel(defaults: defaults).shortcut == .commandOptionA)
      defaults.set(
        Data(#"{"keyCode":999,"modifiers":256,"keyLabel":"A"}"#.utf8), forKey: "customShortcut")
      #expect(AppModel(defaults: defaults).shortcut == .commandOptionA)
      defaults.set("unknown", forKey: "shortcut")
      #expect(AppModel(defaults: defaults).shortcut == .commandShift2)
    }
  }

  @Test func customSettingsPersistAndRegistrationFailurePreservesOldValue() throws {
    try withModel { defaults, model in
      let custom = try CaptureShortcut.validated(
        keyCode: 0, modifiers: UInt32(controlKey | shiftKey), keyLabel: "A")
      #expect(model.registerShortcut(custom, using: { _ in }))
      #expect(AppModel(defaults: defaults).shortcut == custom)
      let stored = defaults.data(forKey: "customShortcut")
      #expect(!model.registerShortcut(.commandOptionA, using: { _ in throw HotKeyError.conflict }))
      #expect(model.shortcut == custom && model.shortcutActive)
      #expect(model.error != nil)
      #expect(defaults.data(forKey: "customShortcut") == stored)
    }
  }

  @Test func recorderConsumesValidKeyAndSavesOnlyAfterRegistration() throws {
    try withRecording { _, model, recorder, window in
      model.changeShortcut = { [weak model] shortcut in
        model?.registerShortcut(shortcut, using: { _ in }) ?? false
      }
      let event = try key(0, flags: [.control, .shift, .capsLock], characters: "A", window: window)
      #expect(recorder.handle(event) == nil)
      #expect(!recorder.isRecording && !model.isRecordingShortcut)
      #expect(model.shortcut.keyCode == 0)
      #expect(model.shortcut.modifiers == UInt32(controlKey | shiftKey))
      #expect(!recorder.hasError)
      #expect(model.recordExistingShortcut == nil)
    }
  }

  @Test func invalidAndConflictingCombinationsKeepRecording() throws {
    try withRecording { _, model, recorder, window in
      let original = model.shortcut
      let plainKey = try key(0, flags: [], characters: "a", window: window)
      #expect(recorder.handle(plainKey) == nil)
      #expect(recorder.isRecording && recorder.hasError)
      #expect(model.shortcut == original)
      model.changeShortcut = { [weak model] shortcut in
        model?.registerShortcut(shortcut, using: { _ in throw HotKeyError.conflict }) ?? false
      }
      let combination = try key(0, flags: [.control, .shift], characters: "A", window: window)
      #expect(recorder.handle(combination) == nil)
      #expect(recorder.isRecording && recorder.hasError)
      #expect(model.shortcut == original)
    }
  }

  @Test func escapeAndWindowBlurCancelWithoutChangingPreferences() throws {
    try withRecording { defaults, model, recorder, window in
      let escape = try key(53, flags: [], characters: "\u{1b}", window: window)
      #expect(recorder.handle(escape) == nil)
      #expect(!recorder.isRecording && !model.isRecordingShortcut)
      #expect(defaults.data(forKey: "customShortcut") == nil)
      recorder.start(model: model, window: window)
      NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
      #expect(!recorder.isRecording && !model.isRecordingShortcut)
      #expect(defaults.data(forKey: "customShortcut") == nil)
    }
  }

  @Test func pressingExistingHotKeyCompletesWithoutStartingCapture() throws {
    try withRecording { _, model, recorder, _ in
      model.changeShortcut = { [weak model] shortcut in
        model?.registerShortcut(shortcut, using: { _ in }) ?? false
      }
      model.recordExistingShortcut?()
      #expect(!recorder.isRecording && !model.isRecordingShortcut)
      #expect(model.shortcut == .commandShift2)
      #expect(!recorder.hasError)
    }
  }

  @Test func repeatedKeyIsIgnoredAndOutsideClickCancels() throws {
    try withRecording { _, model, recorder, window in
      let repeated = try key(
        0, flags: [.control, .shift], characters: "A", window: window, isRepeat: true)
      #expect(recorder.handle(repeated) == nil)
      #expect(recorder.isRecording)
      let click = try #require(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: .zero, modifierFlags: [],
          timestamp: 0, windowNumber: window.windowNumber, context: nil,
          eventNumber: 1, clickCount: 1, pressure: 1))
      #expect(recorder.handle(click) === click)
      #expect(!recorder.isRecording && !model.isRecordingShortcut)
    }
  }

  private func withModel(_ body: (UserDefaults, AppModel) throws -> Void) throws {
    let suite = "FeatherShortcutTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(defaults, AppModel(defaults: defaults))
  }

  private func withRecording(
    _ body: (UserDefaults, AppModel, ShortcutRecorder, NSWindow) throws -> Void
  ) throws {
    _ = NSApplication.shared
    try withModel { defaults, model in
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 300, height: 200),
        styleMask: .borderless, backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let recorder = ShortcutRecorder()
      defer {
        recorder.cancel()
        window.close()
      }
      recorder.start(model: model, window: window)
      #expect(recorder.isRecording && model.isRecordingShortcut)
      try body(defaults, model, recorder, window)
    }
  }

  private func key(
    _ code: UInt16, flags: NSEvent.ModifierFlags, characters: String,
    window: NSWindow, isRepeat: Bool = false
  ) throws -> NSEvent {
    try #require(
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: characters.lowercased(), isARepeat: isRepeat, keyCode: code))
  }
}
