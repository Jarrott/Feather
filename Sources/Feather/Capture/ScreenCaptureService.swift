import AppKit
import ScreenCaptureKit

/// 一次捕捉的屏幕和静态原图，仅在截图会话中持有，不持久化屏幕内容。
@MainActor
struct ScreenSnapshot {
  let screen: NSScreen
  let image: CGImage
}

/// 通过 ScreenCaptureKit 获取真实授权结果；不把 CoreGraphics 的预检查当作截图门禁。
@MainActor
enum ScreenCaptureService {
  /// 用户主动截图时逐屏读取静态帧，排除本进程窗口；系统负责权限提示，失败原样抛出。
  /// showCursor 决定是否包含指针，不录制音视频，不缓存授权，也不修改系统权限。
  static func capture(showCursor: Bool) async throws -> [ScreenSnapshot] {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    let ownWindows = content.windows.filter {
      $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
    }
    var snapshots: [ScreenSnapshot] = []
    for screen in NSScreen.screens {
      try Task.checkCancellation()
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber,
        let display = content.displays.first(where: { $0.displayID == number.uint32Value })
      else { continue }
      let configuration = SCStreamConfiguration()
      configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
      configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
      configuration.showsCursor = showCursor
      configuration.captureResolution = .best
      let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
      let image = try await SCScreenshotManager.captureImage(
        contentFilter: filter, configuration: configuration)
      snapshots.append(ScreenSnapshot(screen: screen, image: image))
    }
    return snapshots
  }

  /// 只把 ScreenCaptureKit 的 userDeclined 识别为授权失败，避免把其他错误误报成权限问题。
  static func isPermissionDenied(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == SCStreamErrorDomain
      && error.code == SCStreamError.Code.userDeclined.rawValue
  }
}
