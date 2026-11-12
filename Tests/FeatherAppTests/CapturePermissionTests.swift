import AppKit
import ScreenCaptureKit
import Testing

@testable import Feather

/// 使用注入的捕捉提供器回归授权状态，不读取桌面、不弹系统授权框、不修改 TCC。
@MainActor
@Suite(.serialized)
struct CapturePermissionTests {
  private func withModel(_ body: (AppModel) async throws -> Void) async throws {
    let suite = "FeatherPermissionTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    try await body(AppModel(defaults: defaults))
  }

  @Test func negativePreflightDoesNotPreventSystemCaptureAttempt() async throws {
    try await withModel { model in
      model.permissionGranted = false
      model.showCursor = true
      var attempted = false
      var completed = 0
      var receivedError: Error?
      let capture = CaptureCoordinator(model: model) { showCursor in
        attempted = true
        #expect(showCursor)
        return []
      }
      capture.onComplete = { completed += 1 }
      capture.onError = { receivedError = $0 }
      capture.start()
      for _ in 0..<100 where completed == 0 { try await Task.sleep(for: .milliseconds(10)) }
      #expect(attempted)
      #expect(completed == 1)
      #expect(receivedError is CaptureError)
      capture.cancel()
      #expect(completed == 1)
    }
  }

  @Test func denialMustMatchTheSystemDomainAndCode() {
    #expect(ScreenCaptureService.isPermissionDenied(denied()))
    #expect(
      !ScreenCaptureService.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: -3801)))
    #expect(
      !ScreenCaptureService.isPermissionDenied(NSError(domain: SCStreamErrorDomain, code: -3802)))
    #expect(!ScreenCaptureService.isPermissionDenied(CancellationError()))
  }

  @Test func repeatedStartOnlyRequestsCaptureOnce() async throws {
    try await withModel { model in
      var attempts = 0
      var completions = 0
      let capture = CaptureCoordinator(model: model) { _ in
        attempts += 1
        return []
      }
      capture.onComplete = { completions += 1 }
      capture.start()
      capture.start()
      for _ in 0..<100 where completions == 0 { try await Task.sleep(for: .milliseconds(10)) }
      capture.start()
      await Task.yield()
      #expect(attempts == 1 && completions == 1)
    }
  }

  @Test func actualDenialClearsPreviouslyGrantedState() async throws {
    try await verifyFailure(denied(), expectedPermission: false)
  }

  @Test func unrelatedCaptureFailureDoesNotClearPermission() async throws {
    try await verifyFailure(
      NSError(domain: SCStreamErrorDomain, code: -3802), expectedPermission: true)
  }

  @Test func cancelledRequestDoesNotShowALatePermissionError() async throws {
    try await withModel { model in
      model.permissionGranted = true
      var entered = false
      var finished = 0
      var errors = 0
      let capture = CaptureCoordinator(model: model) { _ in
        entered = true
        // 模拟系统请求无法立即取消，最后才返回授权拒绝的情形。
        try? await Task.sleep(for: .seconds(2))
        throw denied()
      }
      capture.onComplete = { finished += 1 }
      capture.onError = { _ in errors += 1 }
      capture.start()
      for _ in 0..<100 where !entered { try await Task.sleep(for: .milliseconds(10)) }
      #expect(entered)
      capture.cancel()
      try await Task.sleep(for: .milliseconds(30))
      #expect(finished == 1 && errors == 0)
      #expect(model.permissionGranted)
    }
  }

  @Test func screenChangesOnlyEndEditingWhenTheEditedDisplayChanges() {
    let main = CaptureDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    let other = CaptureDisplay(
      id: 2, frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1)
    // 框选阶段尚无编辑屏幕，任何变化都取消。
    #expect(CaptureCoordinator.shouldCancel(editing: nil, current: [main, other]))
    #expect(!CaptureCoordinator.shouldCancel(editing: main, current: [main]))
    #expect(!CaptureCoordinator.shouldCancel(editing: main, current: [other, main]))
    #expect(CaptureCoordinator.shouldCancel(editing: other, current: [main]))
    let rescaled = CaptureDisplay(id: 1, frame: main.frame, scale: 1)
    #expect(CaptureCoordinator.shouldCancel(editing: main, current: [rescaled]))
  }

  private func verifyFailure(_ failure: Error, expectedPermission: Bool) async throws {
    try await withModel { model in
      model.permissionGranted = true
      var received: Error?
      let capture = CaptureCoordinator(model: model) { _ in throw failure }
      capture.onError = { received = $0 }
      capture.start()
      for _ in 0..<100 where received == nil { try await Task.sleep(for: .milliseconds(10)) }
      #expect((received as NSError?)?.code == (failure as NSError).code)
      #expect(model.permissionGranted == expectedPermission)
    }
  }

  private func denied() -> NSError {
    NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
  }
}
