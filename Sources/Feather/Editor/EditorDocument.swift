import AppKit
import FeatherCore
import SwiftUI
import UniformTypeIdentifiers

/// 单张截图会话；编辑留在主线程，像素合成、PNG 编码与磁盘写入使用独立后台任务。
@MainActor
final class EditorDocument: NSObject, ObservableObject {
  @Published private(set) var image: CGImage
  let appModel: AppModel
  private let pasteboard: NSPasteboard
  private let renderPNG: @Sendable (CGImage, [Annotation]) throws -> Data
  private var source: CGImage?
  private(set) var exportTask: Task<Void, Never>?
  @Published var tool: AnnotationTool = .arrow
  @Published var isSelectingRegion = true
  @Published var color = InkColor.palette[0]
  @Published var lineWidth: CGFloat = 4
  @Published var fontSize: CGFloat = 28
  @Published var history = AnnotationHistory() {
    didSet {
      if history.cropRect != oldValue.cropRect, let rect = history.cropRect,
        let crop = source?.cropping(to: rect)
      {
        image = crop
      }
      savedURL = nil
      status = nil
    }
  }
  @Published var isExporting = false
  @Published var status: String?
  @Published var error: String?
  @Published var savedURL: URL?
  var onClose: (() -> Void)?
  var onPin: ((CGImage) -> Bool)?
  var commitText: (() -> Void)?

  /// 注入剪贴板和纯渲染函数供隔离测试；初始化不读取屏幕、不写入文件或剪贴板。
  init(
    image: CGImage, appModel: AppModel, pasteboard: NSPasteboard = .general,
    renderPNG: @escaping @Sendable (CGImage, [Annotation]) throws -> Data = AnnotationRenderer.png
  ) {
    self.image = image
    self.appModel = appModel
    self.pasteboard = pasteboard
    self.renderPNG = renderPNG
  }

  /// 建立冻结原图与裁剪范围；后续撤销只保存几何信息，不复制每一步的全屏图。
  func configureCrop(source: CGImage, rect: CGRect) {
    self.source = source
    history.previewCrop(rect)
  }

  /// 选区拖动预览；输入须为原图内像素矩形，导出时拒绝修改。
  func previewCrop(_ rect: CGRect) {
    guard !isExporting, let source,
      CGRect(x: 0, y: 0, width: source.width, height: source.height).contains(rect)
    else { return }
    history.previewCrop(rect)
  }

  /// 兼容旧调用方的裁剪更新；新交互使用 previewCrop 和 commitCrop 记录一次完整拖动。
  func updateCrop(_ image: CGImage, annotationOffset: CGPoint) {
    guard !isExporting else { return }
    self.image = image
    history.translate(by: annotationOffset)
  }

  /// 切换工具前提交内联文字；再次点击同一工具可回到移动模式。
  func selectTool(_ candidate: AnnotationTool, toggleSelection: Bool = false) {
    guard !isExporting else { return }
    commitText?()
    let deselect = toggleSelection && !isSelectingRegion && tool == candidate
    tool = candidate
    isSelectingRegion = deselect
  }

  /// 添加标注；达到数量上限时保留原内容并显示本地化提示。
  func add(_ annotation: Annotation) {
    guard !isExporting else { return }
    if !history.append(annotation) { error = L.text("editor.limit") }
  }

  /// 提交标注移动；导出锁定时拒绝，历史记录由模型统一维护。
  func moveAnnotation(id: UUID, by offset: CGPoint) {
    guard !isExporting else { return }
    history.move(id: id, by: offset)
  }

  /// 删除指定标注并记录原层级，支持撤销；导出时保留原内容。
  func deleteAnnotation(id: UUID) {
    guard !isExporting else { return }
    history.remove(id: id)
  }

  /// 工具条和键盘共用编辑历史；文字编辑先落入同一撤销栈。
  func undo() {
    guard !isExporting else { return }
    commitText?()
    history.undo()
  }
  func redo() {
    guard !isExporting else { return }
    commitText?()
    history.redo()
  }

  /// 后台合成并编码后在主线程写剪贴板；同步锁定导出状态，失败保留会话。
  func copy(closeAfter: Bool = false) { export(.copy, closeAfter: closeAfter) }

  /// 后台生成贴图；图片仅交给窗口持有，不自动写文件。
  func pin() { export(.pin, closeAfter: true) }

  /// 另存为面板确认后再导出；编码与文件写入均不占用主线程，取消面板不改变会话。
  func save(asNewLocation: Bool = false, closeAfter: Bool = false) {
    guard !isExporting else { return }
    commitText?()
    var chosenURL: URL?
    if asNewLocation {
      let panel = NSSavePanel()
      panel.allowedContentTypes = [.png]
      panel.canCreateDirectories = true
      panel.directoryURL = appModel.saveDirectory
      panel.nameFieldStringValue =
        (try? FilenameTemplate.filename(
          template: appModel.filenameTemplate,
          size: CGSize(width: image.width, height: image.height))) ?? "Feather.png"
      panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
      guard panel.runModal() == .OK, let url = panel.url else { return }
      chosenURL = url
    }
    export(.save(chosenURL), closeAfter: closeAfter)
  }

  private enum Destination: Sendable {
    case copy
    case save(URL?)
    case pin
  }

  /// 快照不可变输入后启动后台工作；只有成功才关闭，状态、剪贴板与窗口操作留在主线程。
  private func export(_ destination: Destination, closeAfter: Bool) {
    guard !isExporting else { return }
    commitText?()
    isExporting = true
    error = nil
    let image = image
    let annotations = history.annotations
    let directory = appModel.saveDirectory
    let template = appModel.filenameTemplate
    let copyAfterSave = appModel.copyAfterSave
    let render = renderPNG
    exportTask = Task {
      defer { isExporting = false }
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try autoreleasepool {
            // 贴图只需位图，直接合成，跳过 PNG 编码与解码。
            if case .pin = destination {
              let pinned = try AnnotationRenderer.composite(image: image, annotations: annotations)
              return (Data(), URL?.none, CGImage?.some(pinned))
            }
            let data = try render(image, annotations)
            var url: URL?
            if case .save(let chosen) = destination {
              if let chosen {
                try data.write(to: chosen, options: .atomic)
                url = chosen
              } else {
                url = try PNGExporter.save(
                  data, to: directory, template: template,
                  imageSize: CGSize(width: image.width, height: image.height))
              }
            }
            return (data, url, CGImage?.none)
          }
        }.value
        switch destination {
        case .copy:
          guard PasteboardWriter.write(result.0, to: pasteboard) else {
            error = L.text("copy.failed")
            return
          }
          status = L.text("copy.success")
        case .save:
          savedURL = result.1
          status = L.text("save.success")
          if copyAfterSave, !PasteboardWriter.write(result.0, to: pasteboard) {
            error = L.text("copy.failedAfterSave")
            return
          }
        case .pin:
          guard let image = result.2, onPin?(image) == true else {
            error = L.text("pin.failed")
            return
          }
        }
        if closeAfter {
          isExporting = false
          onClose?()
        }
      } catch { self.error = Self.message(for: error) }
    }
  }

  /// 内核保持稳定英文错误，用户界面映射本地化；未知文件系统错误由系统本地化。
  static func message(for error: Error) -> String {
    guard let error = error as? ExportError else { return error.localizedDescription }
    return switch error {
    case .renderFailed: L.text("export.renderFailed")
    case .invalidPNG: L.text("export.invalidPNG")
    case .invalidDirectory: L.text("export.invalidDirectory")
    case .invalidFilename: L.text("export.invalidFilename")
    }
  }
}
