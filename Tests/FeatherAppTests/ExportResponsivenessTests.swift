import AppKit
import FeatherCore
import Testing

@testable import Feather

@MainActor
@Suite(.serialized)
struct ExportResponsivenessTests {
  /// 阻塞注入的编码器，证明 MainActor 可继续运行且重复确认不会创建第二次导出。
  @Test func pngEncodingNeverBlocksMainActorAndLocksCopyUntilComplete() async throws {
    let suite = "FeatherExportTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let gate = DispatchSemaphore(value: 0)
    let document = EditorDocument(
      image: image, appModel: AppModel(defaults: defaults), pasteboard: pasteboard
    ) { image, annotations in
      #expect(!Thread.isMainThread)
      #expect(gate.wait(timeout: .now() + 3) == .success)
      return try AnnotationRenderer.png(image: image, annotations: annotations)
    }
    document.add(
      Annotation(tool: .text, points: [.zero], color: .palette[0], text: "中文 A", fontSize: 20))
    var closed = 0
    document.onClose = { closed += 1 }
    document.copy(closeAfter: true)
    document.copy(closeAfter: true)
    #expect(document.isExporting)
    await Task.yield()
    #expect(closed == 0)
    gate.signal()
    await document.exportTask?.value
    #expect(closed == 1 && !document.isExporting && document.error == nil)
    #expect(pasteboard.data(forType: .png) != nil)
  }

  @Test func failedEncodingPreservesClipboardAndPinUsesCompletedImage() async throws {
    let suite = "FeatherExportFailure.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("preserved", forType: .string)
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    let model = AppModel(defaults: defaults)
    let failed = EditorDocument(image: image, appModel: model, pasteboard: pasteboard) { _, _ in
      throw ExportError.renderFailed
    }
    failed.copy(closeAfter: true)
    await failed.exportTask?.value
    #expect(!failed.isExporting && failed.error == L.text("export.renderFailed"))
    #expect(pasteboard.string(forType: .string) == "preserved")
    let pinned = EditorDocument(image: image, appModel: model, pasteboard: pasteboard)
    var received = false
    var closed = false
    pinned.onPin = { result in
      received = result.width == 64 && result.height == 64
      return true
    }
    pinned.onClose = { closed = true }
    pinned.pin()
    await pinned.exportTask?.value
    #expect(received && closed && pinned.savedURL == nil)
    #expect(pasteboard.string(forType: .string) == "preserved")
    pinned.onPin = { _ in false }
    closed = false
    pinned.pin()
    await pinned.exportTask?.value
    #expect(!closed && pinned.error == L.text("pin.failed"))
  }

  /// 贴图直接合成位图，不依赖 PNG 编码器；贴图窗口在应用切到后台后仍保持显示。
  @Test func pinComposesWithoutEncodingAndStaysVisibleAfterDeactivation() async throws {
    _ = NSApplication.shared
    let suite = "FeatherPinTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let context = try #require(
      CGContext(
        data: nil, width: 64, height: 64, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let image = try #require(context.makeImage())
    let model = AppModel(defaults: defaults)
    let document = EditorDocument(image: image, appModel: model) { _, _ in
      Issue.record("pin must not encode PNG")
      throw ExportError.renderFailed
    }
    document.add(
      Annotation(
        tool: .redact, points: [CGPoint(x: 0, y: 0), CGPoint(x: 32, y: 32)],
        color: .palette[0]))
    let controller = PinnedImageController(displaysWindows: false)
    document.onPin = { result in
      let bitmap = NSBitmapImageRep(cgImage: result)
      #expect(bitmap.colorAt(x: 16, y: 16)?.redComponent == 0)
      #expect(bitmap.colorAt(x: 48, y: 48)?.redComponent == 1)
      return controller.pin(result, model: model)
    }
    document.pin()
    await document.exportTask?.value
    #expect(document.error == nil)
    let window = try #require(controller.windows.first)
    defer { window.close() }
    #expect(!window.hidesOnDeactivate && window.level == .floating)
    #expect(!window.isVisible)
  }

  @Test func clipboardFailureRestoresAllOriginalTypesAndItems() throws {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let first = NSPasteboardItem()
    let second = NSPasteboardItem()
    first.setString("previous text", forType: .string)
    first.setData(Data([1, 2, 3]), forType: .rtf)
    second.setString("second", forType: .string)
    #expect(pasteboard.writeObjects([first, second]))
    #expect(!PasteboardWriter.write(Data([9]), to: pasteboard, writer: { _, _ in false }))
    let restored = try #require(pasteboard.pasteboardItems)
    #expect(restored.count == 2)
    #expect(restored[0].string(forType: .string) == "previous text")
    #expect(restored[0].data(forType: .rtf) == Data([1, 2, 3]))
    #expect(restored[1].string(forType: .string) == "second")
  }

  @Test func clipboardFailureDoesNotOverwriteAnotherWritersContent() {
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("old", forType: .string)
    #expect(
      !PasteboardWriter.write(
        Data([9]), to: pasteboard,
        writer: { board, _ in
          board.clearContents()
          board.setString("another application", forType: .string)
          return false
        }))
    #expect(pasteboard.string(forType: .string) == "another application")
  }

  @Test func exportErrorsUseUILocalizationAndPermissionsStartUnknown() throws {
    let defaults = try #require(UserDefaults(suiteName: "FeatherErrorTests"))
    defer { defaults.removePersistentDomain(forName: "FeatherErrorTests") }
    let model = AppModel(defaults: defaults)
    #expect(!model.permissionKnown)
    model.permissionGranted = true
    #expect(model.permissionKnown && model.permissionGranted)
    #expect(
      EditorDocument.message(for: ExportError.invalidDirectory) == L.text("export.invalidDirectory")
    )
    #expect(model.setFilenameTemplate("Capture_{width}_{height}"))
    #expect(!model.setFilenameTemplate("../invalid"))
    #expect(model.filenameTemplate == "Capture_{width}_{height}")
  }
}
