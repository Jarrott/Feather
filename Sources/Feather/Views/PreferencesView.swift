import SwiftUI

/// 菜单栏右键打开的精简设置；仅保留截图快捷键、输出目录、复制与鼠标选项。
struct PreferencesView: View {
  @ObservedObject var model: AppModel
  @State private var filenameTemplate = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack(spacing: 10) {
          Image(systemName: "viewfinder").font(.system(size: 26)).foregroundStyle(Theme.accent)
          VStack(alignment: .leading, spacing: 4) {
            Text(L.text("app.name")).font(.system(size: 18, weight: .semibold))
            Text(L.text("menu.tooltip")).font(.system(size: 11)).foregroundStyle(Theme.muted)
          }
          Spacer()
          Text("v1.4.0").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
        }
        if let error = model.error {
          Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11))
            .foregroundStyle(.red)
        }
        if let status = model.status {
          Text(status).font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        ShortcutSettingsView(model: model)
        VStack(alignment: .leading, spacing: 15) {
          Text(L.text("settings.location")).font(.system(size: 13, weight: .medium))
          HStack {
            Image(systemName: "folder").foregroundStyle(Theme.accent)
            Text(model.saveDirectory.path).font(.system(size: 11)).lineLimit(1).truncationMode(
              .middle)
            Spacer()
            Button(L.text("settings.choose")) { model.chooseDirectory() }.buttonStyle(
              QuietButtonStyle())
          }
          Divider()
          Text(L.text("settings.filename")).font(.system(size: 12, weight: .medium))
          HStack {
            TextField(L.text("settings.filename"), text: $filenameTemplate)
              .textFieldStyle(.roundedBorder)
              .onSubmit { _ = model.setFilenameTemplate(filenameTemplate) }
            Button(L.text("settings.apply")) { _ = model.setFilenameTemplate(filenameTemplate) }
          }
          Text(L.text("settings.filenameHint")).font(.system(size: 10)).foregroundStyle(Theme.muted)
          Divider()
          Toggle(L.text("settings.copy"), isOn: $model.copyAfterSave).toggleStyle(.switch)
            .controlSize(.small)
          Toggle(L.text("settings.cursor"), isOn: $model.showCursor).toggleStyle(.switch)
            .controlSize(.small)
        }.font(.system(size: 12)).padding(20).background(
          .white, in: RoundedRectangle(cornerRadius: 10))
        HStack {
          Label(
            L.text(
              !model.permissionKnown
                ? "permission.unknown"
                : model.permissionGranted ? "permission.ready" : "permission.needed"),
            systemImage: model.permissionGranted ? "checkmark.circle" : "exclamationmark.circle"
          )
          .foregroundStyle(model.permissionGranted ? Theme.accent : .orange)
          Spacer()
          Button(L.text("permission.settings")) { model.openPrivacySettings() }.buttonStyle(.link)
        }.font(.system(size: 11))
      }.padding(22)
    }.onAppear { filenameTemplate = model.filenameTemplate }.background(Theme.background)
      .foregroundStyle(Theme.ink).environment(\.colorScheme, .light)
  }
}

/// 全局热键预设与按键录制；新组合注册成功后才更新选择值，离开设置立即停止监听。
struct ShortcutSettingsView: View {
  @ObservedObject var model: AppModel
  @StateObject private var recorder = ShortcutRecorder()

  var body: some View {
    VStack(alignment: .leading, spacing: 23) {
      VStack(alignment: .leading, spacing: 18) {
        Label(L.text("shortcut.global"), systemImage: "globe").font(
          .system(size: 14, weight: .semibold))
        Text(L.text("shortcut.detail")).font(.system(size: 12)).foregroundStyle(Theme.muted)
        HStack {
          Text(L.text("capture.start")).font(.system(size: 13))
          Spacer()
          Picker(
            L.text("shortcut.preset"),
            selection: Binding(get: { model.shortcut }, set: { _ = model.changeShortcut?($0) })
          ) {
            if !CaptureShortcut.presets.contains(model.shortcut) {
              Text(L.format("shortcut.customValue", model.shortcut.title)).tag(model.shortcut)
            }
            ForEach(CaptureShortcut.presets, id: \.self) { preset in Text(preset.title).tag(preset)
            }
          }.labelsHidden().frame(width: 185).disabled(recorder.isRecording)
        }
        HStack(spacing: 12) {
          Button {
            recorder.start(model: model, window: NSApp.keyWindow)
          } label: {
            Label(
              L.text(recorder.isRecording ? "shortcut.recording" : "shortcut.record"),
              systemImage: recorder.isRecording ? "record.circle" : "keyboard")
          }.buttonStyle(QuietButtonStyle()).disabled(recorder.isRecording)
          if recorder.isRecording {
            Text(recorder.modifierPreview + L.text("shortcut.pressKey"))
              .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(
                Theme.accent)
            Spacer()
            Button(L.text("cancel")) { recorder.cancel() }.buttonStyle(.plain)
              .font(.system(size: 12)).foregroundStyle(Theme.muted)
          }
        }
        Text(L.text("shortcut.recordHint")).font(.system(size: 11)).foregroundStyle(Theme.muted)
        if let message = recorder.message {
          Label(
            message,
            systemImage: recorder.hasError ? "exclamationmark.circle" : "checkmark.circle.fill"
          )
          .font(.system(size: 11)).foregroundStyle(recorder.hasError ? Color.red : Theme.accent)
        }
        Label(
          L.text(model.shortcutActive ? "shortcut.active" : "shortcut.inactive"),
          systemImage: model.shortcutActive ? "checkmark.circle.fill" : "exclamationmark.circle"
        )
        .font(.system(size: 11)).foregroundStyle(model.shortcutActive ? Theme.accent : .orange)
      }.padding(24).background(.white, in: RoundedRectangle(cornerRadius: 12))
    }.onDisappear { recorder.cancel() }
  }

}
