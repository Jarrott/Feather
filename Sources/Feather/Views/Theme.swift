import SwiftUI

enum Theme {
  static let ink = Color(red: 0.10, green: 0.16, blue: 0.15)
  static let muted = Color(red: 0.46, green: 0.51, blue: 0.49)
  static let accent = Color(red: 0.05, green: 0.55, blue: 0.42)
  static let mint = Color(red: 0.70, green: 0.95, blue: 0.83)
  static let background = Color(red: 0.96, green: 0.97, blue: 0.96)
  static let line = Color.black.opacity(0.07)
}

struct PrimaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .semibold))
      .padding(.horizontal, 18).padding(.vertical, 12)
      .foregroundStyle(.white)
      .background(
        Theme.accent.opacity(configuration.isPressed ? 0.75 : 1),
        in: RoundedRectangle(cornerRadius: 9))
  }
}

struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 13).padding(.vertical, 9)
      .background(
        configuration.isPressed ? Theme.line : Color.white, in: RoundedRectangle(cornerRadius: 8)
      )
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
  }
}

struct ShortcutBadge: View {
  let text: String
  var body: some View {
    Text(text).font(.system(size: 12, weight: .medium, design: .monospaced))
      .padding(.horizontal, 9).padding(.vertical, 5)
      .background(Theme.background, in: RoundedRectangle(cornerRadius: 5))
      .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.line))
  }
}
