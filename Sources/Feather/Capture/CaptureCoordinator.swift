import AppKit
import FeatherCore

/// 每次截图创建一次协调器；仅取静态帧，结束或取消后释放全部屏幕缓存。
@MainActor
final class CaptureCoordinator {
  var onComplete: (() -> Void)?
  var onError: ((Error) -> Void)?
  private var windows: [NSWindow] = []
  private var task: Task<Void, Never>?
  private var screenObserver: NSObjectProtocol?
  private let showCursor: Bool
  private let model: AppModel
  private let captureScreens: (Bool) async throws -> [ScreenSnapshot]
  private var document: EditorDocument?
  private var finished = false

  /// 注入静态帧提供器便于隔离测试；默认由系统执行权限检查，预检查为 false 也会尝试捕捉。
  init(
    model: AppModel,
    captureScreens: @escaping (Bool) async throws -> [ScreenSnapshot] = ScreenCaptureService.capture
  ) {
    self.model = model
    self.showCursor = model.showCursor
    self.captureScreens = captureScreens
  }

  /// 截图过程中重复触发仅聚焦当前选区；不创建第二次捕捉或独立编辑器。
  func focus() { windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil) }

  var isExporting: Bool { document?.isExporting == true }

  /// 异步读取可分享显示器，排除自身窗口；权限或系统错误会关闭覆盖层并通知调用方。
  func start() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.cancel() } }
    task = Task { [weak self] in
      guard let self else { return }
      do {
        // 等待设置窗口隐藏后的系统合成帧，避免把设置内容截入图片。
        try await Task.sleep(for: .milliseconds(180))
        let snapshots = try await captureScreens(showCursor)
        try Task.checkCancellation()
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        model.permissionGranted = true
        for snapshot in snapshots { present(screen: snapshot.screen, image: snapshot.image) }
        NSApp.activate(ignoringOtherApps: true)
        let active = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        active?.makeKeyAndOrderFront(nil)
      } catch is CancellationError {
        finish()
      } catch {
        guard !finished, !Task.isCancelled else { return }
        if ScreenCaptureService.isPermissionDenied(error) { model.permissionGranted = false }
        finish()
        onError?(error)
      }
    }
  }

  /// 取消任何尚未完成的系统请求并释放窗口；可重复调用，不写入文件或剪贴板。
  func cancel() {
    guard !isExporting else { return }
    task?.cancel()
    finish()
  }

  private func present(screen: NSScreen, image: CGImage) {
    let window = CaptureWindow(
      contentRect: screen.frame, styleMask: .borderless,
      backing: .buffered, defer: false, screen: screen)
    window.setFrame(screen.frame, display: false)
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isOpaque = true
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    let view = SelectionView(image: image, frame: CGRect(origin: .zero, size: screen.frame.size))
    view.onCancel = { [weak self] in self?.cancel() }
    view.onSelect = { [weak self, weak view, weak window] rect in
      guard
        let pixels = CaptureGeometry.pixelRect(
          selection: rect, viewSize: screen.frame.size,
          imageSize: CGSize(width: image.width, height: image.height)),
        let cropped = image.cropping(to: pixels), let self, let view, let window
      else { return }
      let document = EditorDocument(image: cropped, appModel: self.model)
      self.document = document
      document.onClose = { [weak self] in self?.finish() }
      for other in self.windows where other !== window { other.close() }
      self.windows = [window]
      window.level = .floating
      window.makeKeyAndOrderFront(nil)
      view.beginEditing(document, pixelRect: pixels)
    }
    window.contentView = view
    window.makeFirstResponder(view)
    window.orderFrontRegardless()
    windows.append(window)
  }

  /// 完成或取消时释放截图、工具条和所有屏幕缓存；只通知一次会话结束。
  private func finish() {
    guard !finished else { return }
    finished = true
    if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    screenObserver = nil
    for window in windows { window.close() }
    windows.removeAll()
    document = nil
    onComplete?()
  }
}

private final class CaptureWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

enum CaptureError: LocalizedError {
  case noDisplay
  var errorDescription: String? { L.text("capture.noDisplay") }
}
