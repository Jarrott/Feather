import AppKit

/// 只包含显示器几何的缓存键；位置、缩放或显示器变化都需要重新准备系统过滤器。
struct CaptureDisplay: Equatable, Sendable {
  let id: CGDirectDisplayID
  let frame: CGRect
  let scale: CGFloat
}

/// 已准备的一次性捕捉入口，顺序与显示器一致；闭包只持有系统过滤器，不保留截图。
@MainActor
struct CapturePlan {
  let captures: [@MainActor @Sendable (Bool) async throws -> CGImage]
  let reusable: Bool
}

/// 复用轻量系统过滤器，并发请求每屏静态帧；没有后台录制、预取或屏幕图像缓存。
@MainActor
final class ScreenCapturePipeline {
  private let prepare: @MainActor ([CaptureDisplay]) async throws -> CapturePlan
  private var cached: (displays: [CaptureDisplay], plan: CapturePlan)?

  /// 注入过滤器准备器；生产调用系统，测试可使用自有图像验证并发、失效和错误传播。
  init(prepare: @escaping @MainActor ([CaptureDisplay]) async throws -> CapturePlan) {
    self.prepare = prepare
  }

  /// 按显示器原顺序返回新帧；每次都通过系统捕捉验证授权，失败或取消即清理过滤器缓存。
  /// 只在显示器集合不变且准备器允许复用时跳过枚举；任一屏失败则整批失败，不输出半成品。
  func capture(displays: [CaptureDisplay], showCursor: Bool) async throws -> [CGImage] {
    guard !displays.isEmpty else {
      cached = nil
      return []
    }
    do {
      try Task.checkCancellation()
      let plan: CapturePlan
      if let cached, cached.displays == displays {
        plan = cached.plan
      } else {
        cached = nil
        plan = try await prepare(displays)
        try Task.checkCancellation()
        guard plan.captures.count == displays.count else { throw CaptureError.noDisplay }
        if plan.reusable { cached = (displays, plan) }
      }
      return try await withThrowingTaskGroup(of: (Int, CGImage).self) { group in
        for (index, capture) in plan.captures.enumerated() {
          group.addTask {
            try Task.checkCancellation()
            let image = try await capture(showCursor)
            try Task.checkCancellation()
            return (index, image)
          }
        }
        var results = [CGImage?](repeating: nil, count: plan.captures.count)
        for try await (index, image) in group { results[index] = image }
        try Task.checkCancellation()
        return results.compactMap { $0 }
      }
    } catch {
      cached = nil
      throw error
    }
  }
}
