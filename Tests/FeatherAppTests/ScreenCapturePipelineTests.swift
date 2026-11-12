import AppKit
import ScreenCaptureKit
import Testing

@testable import Feather

/// 用自有小图验证启动调度与缓存；不调用系统截图、不访问桌面或修改权限。
@MainActor
@Suite(.serialized)
struct ScreenCapturePipelineTests {
  private let displays = [
    CaptureDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 80), scale: 2),
    CaptureDisplay(id: 2, frame: CGRect(x: -200, y: 0, width: 200, height: 100), scale: 1),
  ]

  @Test func preparationIsReusedButEveryCaptureGetsFreshFramesAndCursorSetting() async throws {
    var preparations = 0
    var frames = 0
    var cursorValues: [Bool] = []
    let pipeline = ScreenCapturePipeline { screens in
      preparations += 1
      return CapturePlan(
        captures: screens.map { _ in
          { cursor in
            frames += 1
            cursorValues.append(cursor)
            return try image(width: frames)
          }
        }, reusable: true)
    }
    let first = try await pipeline.capture(displays: displays, showCursor: false)
    let second = try await pipeline.capture(displays: displays, showCursor: true)
    #expect(preparations == 1 && frames == 4)
    #expect(first.map(\.width).sorted() == [1, 2])
    #expect(second.map(\.width).sorted() == [3, 4])
    #expect(cursorValues == [false, false, true, true])
    let changed = [CaptureDisplay(id: 1, frame: displays[0].frame, scale: 1)]
    _ = try await pipeline.capture(displays: changed, showCursor: false)
    #expect(preparations == 2)
    _ = try await pipeline.capture(displays: [], showCursor: false)
    _ = try await pipeline.capture(displays: changed, showCursor: false)
    #expect(preparations == 3)
  }

  @Test func screensStartTogetherAndReturnInDisplayOrder() async throws {
    let gate = CaptureGate()
    var started: [Int] = []
    var completed: [Int] = []
    let pipeline = ScreenCapturePipeline { _ in
      CapturePlan(
        captures: [0, 1].map { index in
          { _ in
            started.append(index)
            if index == 0 { await gate.wait() }
            completed.append(index)
            return try image(width: index + 10)
          }
        }, reusable: true)
    }
    let task = Task { try await pipeline.capture(displays: displays, showCursor: false) }
    // 第二屏必须在第一屏尚未完成时启动并完成；不以机器速度为性能断言。
    for _ in 0..<100 where completed.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(started.sorted() == [0, 1] && completed == [1])
    gate.open()
    let images = try await task.value
    #expect(images.map(\.width) == [10, 11])
    #expect(completed == [1, 0])
  }

  @Test func permissionFailureDiscardsPreparedFiltersAndPropagates() async throws {
    var preparations = 0
    var reject = false
    let pipeline = ScreenCapturePipeline { screens in
      preparations += 1
      return CapturePlan(
        captures: screens.map { _ in
          { _ in
            if reject {
              throw NSError(
                domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
            }
            return try image(width: 10)
          }
        }, reusable: true)
    }
    _ = try await pipeline.capture(displays: displays, showCursor: false)
    reject = true
    do {
      _ = try await pipeline.capture(displays: displays, showCursor: false)
      Issue.record("Revoked screen permission must fail the capture")
    } catch {
      #expect(ScreenCaptureService.isPermissionDenied(error))
    }
    reject = false
    _ = try await pipeline.capture(displays: displays, showCursor: false)
    #expect(preparations == 2)
  }

  @Test func cancellationDropsLateFramesAndClearsPreparedFilters() async throws {
    let gate = CaptureGate()
    var preparations = 0
    var started = 0
    let pipeline = ScreenCapturePipeline { screens in
      preparations += 1
      return CapturePlan(
        captures: screens.map { _ in
          { _ in
            started += 1
            await gate.wait()
            return try image(width: 10)
          }
        }, reusable: true)
    }
    let task = Task { try await pipeline.capture(displays: displays, showCursor: false) }
    for _ in 0..<100 where started < 2 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(started == 2)
    task.cancel()
    gate.open()
    do {
      _ = try await task.value
      Issue.record("Cancelled capture must not return late images")
    } catch { #expect(error is CancellationError) }
    _ = try await pipeline.capture(displays: displays, showCursor: false)
    #expect(preparations == 2)
  }

  @Test func windowOnlyPlansAreNotReusedAndIncompletePlansFail() async throws {
    var preparations = 0
    let pipeline = ScreenCapturePipeline { screens in
      preparations += 1
      return CapturePlan(
        captures: screens.map { _ in { _ in try image(width: 10) } }, reusable: false)
    }
    _ = try await pipeline.capture(displays: displays, showCursor: false)
    _ = try await pipeline.capture(displays: displays, showCursor: false)
    #expect(preparations == 2)
    let incomplete = ScreenCapturePipeline { _ in CapturePlan(captures: [], reusable: true) }
    await #expect(throws: CaptureError.self) {
      try await incomplete.capture(displays: displays, showCursor: false)
    }
  }

  @Test func configurationKeepsFullResolutionRGBAndCursorPreference() {
    let config = ScreenCaptureService.configuration(
      pixelSize: CGSize(width: 3840, height: 2160), showCursor: true)
    #expect(config.width == 3840 && config.height == 2160)
    #expect(config.captureResolution == .best && config.pixelFormat == kCVPixelFormatType_32BGRA)
    #expect(config.showsCursor && !config.capturesAudio)
  }

  private func image(width: Int) throws -> CGImage {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    return try #require(context.makeImage())
  }
}

/// 测试用可控系统回调；手动释放所有等待者，验证并发而不读取真实屏幕。
@MainActor
private final class CaptureGate {
  private var released = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  func wait() async {
    if !released { await withCheckedContinuation { waiters.append($0) } }
  }
  func open() {
    released = true
    let pending = waiters
    waiters.removeAll()
    for waiter in pending { waiter.resume() }
  }
}
