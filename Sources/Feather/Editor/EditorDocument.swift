import AppKit
import FeatherCore
import SwiftUI
import UniformTypeIdentifiers

/// 单张截图编辑会话；截图不自动持久化，保存、复制失败时保留全部标注。
@MainActor
final class EditorDocument: NSObject, ObservableObject {
  @Published private(set) var image: CGImage
  let appModel: AppModel
  private let pasteboard: NSPasteboard
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

  /// 创建单张截图会话；默认使用系统剪贴板，测试可传入独立剪贴板以避免覆盖用户内容。
  /// 初始化仅保存图像、设置和输出目标，不读取屏幕、不写入文件或剪贴板。
  init(image: CGImage, appModel: AppModel, pasteboard: NSPasteboard = .general) {
    self.image = image
    self.appModel = appModel
    self.pasteboard = pasteboard
  }

  /// 选择标注工具；按钮再次点击当前工具可回到选区移动模式，数字键则保持绘图模式。
  /// 仅改变交互状态，不修改标注或文件；导出期间忽略切换。
  func selectTool(_ candidate: AnnotationTool, toggleSelection: Bool = false) {
    guard !isExporting else { return }
    let deselect = toggleSelection && !isSelectingRegion && tool == candidate
    tool = candidate
    isSelectingRegion = deselect
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

  /// 将一次标注拖动作为一条可撤销编辑提交；导出时忽略，实际移动后清除过期输出状态。
  func moveAnnotation(id: UUID, by offset: CGPoint) {
    guard !isExporting, history.move(id: id, by: offset) else { return }
    savedURL = nil
    status = nil
  }

  /// 删除一个标注并记为一步可撤销编辑；导出时忽略，实际删除后清除过期输出状态。
  func removeAnnotation(id: UUID) {
    guard !isExporting, history.remove(id: id) else { return }
    savedURL = nil
    status = nil
  }

  /// 像素渲染后写入会话指定的 PNG 剪贴板；失败保留会话，成功可按调用参数关闭窗口。
  func copy(closeAfter: Bool = false) {
    guard !isExporting else { return }
    do {
      let data = try AnnotationRenderer.png(image: image, annotations: history.annotations)
      pasteboard.clearContents()
      guard pasteboard.setData(data, forType: .png) else {
        error = L.text("copy.failed")
        return
      }
      status = L.text("copy.success")
      if closeAfter { onClose?() }
    } catch { self.error = Self.message(for: error) }
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
        // 主线程只合成标注；大图的 PNG 编码与写盘在后台完成，保存期间界面保持响应。
        let composed = try AnnotationRenderer.composite(image: image, annotations: annotations)
        let (data, url) = try await Task.detached(priority: .userInitiated) {
          let data = try AnnotationRenderer.encodePNG(composed)
          if let destination {
            try data.write(to: destination, options: .atomic)
            return (data, destination)
          }
          return (data, try PNGExporter.save(data, to: directory))
        }.value
        savedURL = url
        status = L.text("save.success")
        if appModel.copyAfterSave {
          pasteboard.clearContents()
          if !pasteboard.setData(data, forType: .png) {
            error = L.text("copy.failedAfterSave")
          }
        }
        if closeAfter && error == nil {
          isExporting = false
          onClose?()
        }
      } catch { self.error = L.format("save.failed", Self.message(for: error)) }
    }
  }

  /// 将核心导出错误映射为当前语言文案；其他系统错误沿用系统本地化描述。
  static func message(for error: Error) -> String {
    switch error as? ExportError {
    case .renderFailed: L.text("export.renderFailed")
    case .invalidPNG: L.text("export.invalidPNG")
    case .invalidDirectory: L.text("export.invalidDirectory")
    case nil: error.localizedDescription
    }
  }

}
