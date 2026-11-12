import AppKit
import FeatherCore
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
  private static let pipeline = ScreenCapturePipeline(prepare: prepare)

  /// 用户触发时并发读取各屏原始像素帧；过滤器可复用，截图和权限结果不缓存。
  /// showCursor 决定是否包含指针；系统负责权限提示，任一捕捉失败原样抛出。
  static func capture(showCursor: Bool) async throws -> [ScreenSnapshot] {
    let screens = NSScreen.screens
    let displays = screens.compactMap { screen -> CaptureDisplay? in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
          as? NSNumber
      else { return nil }
      return CaptureDisplay(
        id: number.uint32Value, frame: screen.frame, scale: screen.backingScaleFactor)
    }
    guard displays.count == screens.count else { throw CaptureError.noDisplay }
    let images = try await pipeline.capture(displays: displays, showCursor: showCursor)
    return zip(screens, images).map { ScreenSnapshot(screen: $0, image: $1) }
  }

  /// 枚举当前显示器并按应用排除 Feather 的全部窗口，避免依赖窗口关闭后的固定等待。
  /// 仅缓存过滤器；找不到自身应用时使用本次窗口列表并禁止复用，防止后续窗口漏排除。
  private static func prepare(_ displays: [CaptureDisplay]) async throws -> CapturePlan {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: true)
    let ownApplications = content.applications.filter {
      $0.processID == ProcessInfo.processInfo.processIdentifier
    }
    let ownWindows = content.windows.filter {
      $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
    }
    var captures: [@MainActor @Sendable (Bool) async throws -> CGImage] = []
    for screen in displays {
      guard let display = content.displays.first(where: { $0.displayID == screen.id }) else {
        throw CaptureError.noDisplay
      }
      let filter =
        ownApplications.isEmpty
        ? SCContentFilter(display: display, excludingWindows: ownWindows)
        : SCContentFilter(
          display: display, excludingApplications: ownApplications, exceptingWindows: [])
      guard
        let size = CaptureGeometry.capturePixelSize(
          contentSize: filter.contentRect.size, pointPixelScale: CGFloat(filter.pointPixelScale),
          fallbackSize: screen.frame.size, backingScale: screen.scale
        )
      else { throw CaptureError.noDisplay }
      captures.append { showCursor in
        let configuration = configuration(pixelSize: size, showCursor: showCursor)
        return try await SCScreenshotManager.captureImage(
          contentFilter: filter, configuration: configuration)
      }
    }
    return CapturePlan(captures: captures, reusable: !ownApplications.isEmpty)
  }

  /// 静态截图固定完整 RGB 像素和最佳源分辨率，不使用视频色度抽样；颜色空间由显示器提供。
  static func configuration(pixelSize: CGSize, showCursor: Bool) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.width = Int(pixelSize.width)
    configuration.height = Int(pixelSize.height)
    configuration.showsCursor = showCursor
    configuration.captureResolution = .best
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    return configuration
  }

  /// 只把 ScreenCaptureKit 的 userDeclined 识别为授权失败，避免把其他错误误报成权限问题。
  static func isPermissionDenied(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == SCStreamErrorDomain
      && error.code == SCStreamError.Code.userDeclined.rawValue
  }
}
