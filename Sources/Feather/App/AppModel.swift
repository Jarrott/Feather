import AppKit
import SwiftUI

/// 应用状态和小型偏好存储；只持久化设置，不保存截图副本或历史文件路径。
@MainActor
final class AppModel: ObservableObject {
  @Published var isCapturing = false
  @Published var permissionGranted = CGPreflightScreenCaptureAccess()
  @Published var status: String?
  @Published var error: String?
  @Published private(set) var shortcut: CaptureShortcut
  @Published var isRecordingShortcut = false
  @Published var shortcutActive = false
  @Published var saveDirectory: URL {
    didSet { defaults.set(saveDirectory.path, forKey: "saveDirectory") }
  }
  @Published var copyAfterSave: Bool {
    didSet { defaults.set(copyAfterSave, forKey: "copyAfterSave") }
  }
  @Published var showCursor: Bool {
    didSet { defaults.set(showCursor, forKey: "showCursor") }
  }
  private let defaults: UserDefaults
  var changeShortcut: ((CaptureShortcut) -> Bool)?
  var recordExistingShortcut: (() -> Void)?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    shortcut =
      defaults.data(forKey: "customShortcut").flatMap {
        try? JSONDecoder().decode(CaptureShortcut.self, from: $0)
      } ?? CaptureShortcut.legacyPreset(named: defaults.string(forKey: "shortcut"))
      ?? .commandShift2
    saveDirectory =
      defaults.string(forKey: "saveDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Feather", isDirectory: true)
    copyAfterSave = defaults.object(forKey: "copyAfterSave") as? Bool ?? true
    showCursor = defaults.bool(forKey: "showCursor")

  }

  /// 先编码并注册，再持久化快捷键；注册或编码失败时保留原设置并展示错误。
  /// register 为系统注册函数，测试可注入失败；不申请辅助功能权限。
  @discardableResult
  func registerShortcut(
    _ candidate: CaptureShortcut, using register: (CaptureShortcut) throws -> Void
  ) -> Bool {
    do {
      let data = try JSONEncoder().encode(candidate)
      try register(candidate)
      defaults.set(data, forKey: "customShortcut")
      shortcut = candidate
      shortcutActive = true
      error = nil
      return true
    } catch {
      self.error = error.localizedDescription
      return false
    }
  }

  /// 打开原生目录选择器，仅在用户确定后改变保存位置。
  func chooseDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = saveDirectory
    panel.prompt = L.text("settings.choose")
    if panel.runModal() == .OK, let url = panel.url { saveDirectory = url }
  }

  /// 跳转到系统屏幕录制权限页面；实际授权必须由用户在系统界面完成。
  func openPrivacySettings() {
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
