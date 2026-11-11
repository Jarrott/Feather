import AppKit
import SwiftUI

@main
struct FeatherApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    Settings { PreferencesView(model: delegate.model).frame(width: 560, height: 600) }
  }
}

/// 集中本地化入口；所有界面文案从 SwiftPM 资源包读取，缺失键回退为键本身。
enum L {
  static func text(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
  }

  static func format(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: text(key), locale: Locale.current, arguments: arguments)
  }
}
