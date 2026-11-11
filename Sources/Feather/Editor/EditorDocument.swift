import AppKit
import FeatherCore
import SwiftUI
import UniformTypeIdentifiers

/// 单张截图编辑会话；截图不自动持久化，保存、复制失败时保留全部标注。
@MainActor
final class EditorDocument: NSObject, ObservableObject {
  @Published private(set) var image: CGImage
  let appModel: AppModel
  @Published var tool: AnnotationTool = .arrow
  @Published var isSelectingRegion = true
  @Published var color = InkColor.palette[0]
  @Published var lineWidth: CGFloat = 4
  @Published var history = AnnotationHistory()
  @Published var isExporting = false
  @Published var status: String?
  @Published var error: String?
  @Published var savedURL: URL?
  var onClose: (() -> Void)?

  init(image: CGImage, appModel: AppModel) {
    self.image = image
    self.appModel = appModel
  }

  /// 移动或调整选区后更新原始图片，并平移标注以保持其屏幕位置；保存期间拒绝修改。
  func updateCrop(_ image: CGImage, annotationOffset: CGPoint) {
    guard !isExporting else { return }
    self.image = image
    history.translate(by: annotationOffset)
    savedURL = nil
    status = nil
  }

  /// 添加标注并检查会话上限；无文件副作用，达到上限时展示明确提示。
  func add(_ annotation: Annotation) {
    if !history.append(annotation) { error = L.text("editor.limit") }
    status = nil
  }

  /// 像素渲染后写入 PNG 剪贴板；失败保留会话，成功可按调用参数关闭窗口。
  func copy(closeAfter: Bool = false) {
    guard !isExporting else { return }
    do {
      let data = try AnnotationRenderer.png(image: image, annotations: history.annotations)
      NSPasteboard.general.clearContents()
      guard NSPasteboard.general.setData(data, forType: .png) else {
        error = L.text("copy.failed")
        return
      }
      status = L.text("copy.success")
      if closeAfter { onClose?() }
    } catch { self.error = error.localizedDescription }
  }

  /// 快速保存或显示另存为面板；磁盘写入在后台完成，禁止并行导出和同时修改标注。
  func save(asNewLocation: Bool = false, closeAfter: Bool = false) {
    guard !isExporting else { return }
    var chosenURL: URL?
    if asNewLocation {
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.png]
      panel.canCreateDirectories = true
      panel.directoryURL = appModel.saveDirectory
      panel.nameFieldStringValue = "Feather.png"
      panel.level = .modalPanel
      guard panel.runModal() == .OK, let url = panel.url else { return }
      chosenURL = url
    }
    isExporting = true
    error = nil
    let annotations = history.annotations
    let directory = appModel.saveDirectory
    let destination = chosenURL
    Task {
      defer { isExporting = false }
      do {
        let data = try AnnotationRenderer.png(image: image, annotations: annotations)
        let url = try await Task.detached(priority: .userInitiated) {
          if let destination {
            try data.write(to: destination, options: .atomic)
            return destination
          }
          return try PNGExporter.save(data, to: directory)
        }.value
        savedURL = url
        status = L.text("save.success")
        if appModel.copyAfterSave {
          NSPasteboard.general.clearContents()
          if !NSPasteboard.general.setData(data, forType: .png) {
            error = L.text("copy.failedAfterSave")
          }
        }
        if closeAfter && error == nil {
          isExporting = false
          onClose?()
        }
      } catch { self.error = L.format("save.failed", error.localizedDescription) }
    }
  }

}
