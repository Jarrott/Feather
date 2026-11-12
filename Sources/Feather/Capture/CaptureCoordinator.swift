import AppKit
import FeatherCore

/// 每次截图创建一次协调器；仅取静态帧，结束或取消后释放全部屏幕缓存。
@MainActor
final class CaptureCoordinator {
  var onComplete: (() -> Void)?
  var onError: ((Error) -> Void)?
  private(set) var windows: [NSWindow] = []
  private var task: Task<Void, Never>?
  private var screenObserver: NSObjectProtocol?
  private let displaysWindows: Bool
  private let mode: CaptureMode
  var onPin: ((CGImage) -> Bool)?
  private let showCursor: Bool
  private let model: AppModel
  private let captureScreens: (Bool) async throws -> [ScreenSnapshot]
  private(set) var document: EditorDocument?
  private var finished = false

  /// 注入静态帧提供器便于隔离测试；默认由系统执行权限检查，预检查为 false 也会尝试捕捉。
  init(
    model: AppModel, mode: CaptureMode = .region, displaysWindows: Bool = true,
    captureScreens: @escaping (Bool) async throws -> [ScreenSnapshot] = ScreenCaptureService.capture
  ) {
    self.model = model
    self.mode = mode
    self.displaysWindows = displaysWindows
    self.showCursor = model.showCursor
    self.captureScreens = captureScreens
  }

  /// 截图过程中重复触发仅聚焦当前选区；不创建第二次捕捉或独立编辑器。
  func focus() { windows.first(where: { $0.isVisible })?.makeKeyAndOrderFront(nil) }

  var isExporting: Bool { document?.isExporting == true }

  /// 无固定等待地发起静态捕捉，排除自身窗口；重复启动无操作，权限或系统错误通知调用方。
  func start() {
    guard task == nil, !finished else { return }
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { [weak self] _ in Task { @MainActor in self?.screenParametersChanged() } }
    task = Task { [weak self] in
      guard let self else { return }
      do {
        // 过滤器排除自身应用窗口，直接开始捕捉，不增加固定启动延迟。
        try Task.checkCancellation()
        let snapshots = try await captureScreens(showCursor)
        try Task.checkCancellation()
        guard !snapshots.isEmpty else { throw CaptureError.noDisplay }
        model.permissionGranted = true
        if displaysWindows { NSApp.activate(ignoringOtherApps: true) }
        let active =
          snapshots.first { $0.screen.frame.contains(NSEvent.mouseLocation) } ?? snapshots[0]
        switch mode {
        case .region:
          for snapshot in snapshots { present(screen: snapshot.screen, image: snapshot.image) }
        case .fullScreen, .window:
          present(screen: active.screen, image: active.image, fullSelection: true)
        case .lastRegion:
          guard let saved = model.lastRegion,
            let snapshot = snapshots.first(where: { Self.displayID($0.screen) == saved.displayID }),
            let rect = saved.rect(in: snapshot.screen.frame.size)
          else { throw CaptureError.noLastRegion }
          present(screen: snapshot.screen, image: snapshot.image, initialSelection: rect)
        }
        let activeWindow =
          windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        if displaysWindows { activeWindow?.makeKeyAndOrderFront(nil) }
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

  private func present(
    screen: NSScreen, image: CGImage, fullSelection: Bool = false,
    initialSelection: CGRect? = nil
  ) {
    let window = CaptureWindow(
      contentRect: screen.frame, styleMask: .borderless,
      backing: .buffered, defer: false, screen: screen)
    let frame = mode == .window ? Self.fittedFrame(image: image, in: screen.frame) : screen.frame
    window.setFrame(frame, display: false)
    window.level = .screenSaver
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    window.isOpaque = true
    window.hasShadow = false
    window.isReleasedWhenClosed = false
    let view = SelectionView(image: image, frame: CGRect(origin: .zero, size: frame.size))
    view.onCancel = { [weak self] in self?.cancel() }
    view.onSelect = { [weak self, weak view, weak window] rect in
      guard
        let pixels = CaptureGeometry.pixelRect(
          selection: rect, viewSize: view?.bounds.size ?? frame.size,
          imageSize: CGSize(width: image.width, height: image.height)),
        let cropped = image.cropping(to: pixels), let self, let view, let window
      else { return }
      let document = EditorDocument(image: cropped, appModel: self.model)
      self.document = document
      document.onPin = self.onPin
      document.onClose = { [weak self, weak document] in
        guard let self else { return }
        if self.mode != .window, let rect = document?.history.cropRect,
          let id = Self.displayID(screen)
        {
          self.model.lastRegion = SavedRegion(
            displayID: id,
            normalizedRect: CGRect(
              x: rect.minX / CGFloat(image.width), y: rect.minY / CGFloat(image.height),
              width: rect.width / CGFloat(image.width), height: rect.height / CGFloat(image.height))
          )
        }
        self.finish()
      }
      for other in self.windows where other !== window { other.close() }
      self.windows = [window]
      window.level = .screenSaver
      if self.displaysWindows { window.makeKeyAndOrderFront(nil) }
      view.beginEditing(document, pixelRect: pixels)
    }
    window.contentView = view
    window.makeFirstResponder(view)
    if displaysWindows { window.orderFrontRegardless() }
    windows.append(window)
    if fullSelection {
      view.onSelect?(view.bounds)
    } else if let initialSelection {
      view.onSelect?(initialSelection)
    }
  }

  /// 显示器变化只取消尚未框选的会话；编辑中的冻结图、裁剪和历史保留并移到可用屏幕。
  /// 无可用屏幕时等待下次通知，不重新截取、不丢弃内容；导出也不会被中断。
  func screenParametersChanged(screens: [NSScreen] = NSScreen.screens) {
    guard document != nil else {
      cancel()
      return
    }
    guard let window = windows.first, let view = window.contentView as? SelectionView,
      let screen = screens.first(where: {
        Self.displayID($0) == window.screen.flatMap(Self.displayID)
      }) ?? screens.first
    else { return }
    view.preserveInteraction()
    let frame = Self.fittedFrame(image: view.source, in: screen.frame)
    window.setFrame(frame, display: true)
    window.level = .screenSaver
    view.refresh()
  }

  static func displayID(_ screen: NSScreen) -> UInt32? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  /// 等比例显示冻结源图；屏幕尺寸变化只改变显示比例，输出仍为原图像素。
  private static func fittedFrame(image: CGImage, in bounds: CGRect) -> CGRect {
    let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
    let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
    return CGRect(
      x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
      width: size.width, height: size.height)
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
  case noDisplay, noLastRegion
  var errorDescription: String? {
    switch self {
    case .noDisplay: L.text("capture.noDisplay")
    case .noLastRegion: L.text("capture.noLastRegion")
    }
  }
}
