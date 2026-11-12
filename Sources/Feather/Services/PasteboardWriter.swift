import AppKit

/// 剪贴板替换事务；先准备 PNG 与原内容快照，失败时仅在无人接管剪贴板的情况下恢复。
@MainActor
enum PasteboardWriter {
  /// 写入 PNG；最多备份 64 MiB，无法完整备份时不清空原内容。writer 可注入失败用于隔离测试。
  /// NSPasteboard 不提供跨进程原子事务；检测到其他应用更新时不覆盖其新内容。
  static func write(
    _ data: Data, to pasteboard: NSPasteboard,
    writer: ((NSPasteboard, [NSPasteboardItem]) -> Bool)? = nil
  ) -> Bool {
    let item = NSPasteboardItem()
    guard item.setData(data, forType: .png) else { return false }
    let originalCount = pasteboard.changeCount
    var previous: [NSPasteboardItem] = []
    var byteCount = 0
    for original in pasteboard.pasteboardItems ?? [] {
      let copy = NSPasteboardItem()
      for type in original.types {
        guard let value = original.data(forType: type) else { return false }
        byteCount += value.count
        guard byteCount <= 64 * 1024 * 1024, copy.setData(value, forType: type) else {
          return false
        }
      }
      previous.append(copy)
    }
    guard pasteboard.changeCount == originalCount else { return false }
    let clearedCount = pasteboard.clearContents()
    let succeeded = writer?(pasteboard, [item]) ?? pasteboard.writeObjects([item])
    guard !succeeded else { return true }
    if pasteboard.changeCount == clearedCount {
      pasteboard.clearContents()
      if !previous.isEmpty { _ = pasteboard.writeObjects(previous) }
    }
    return false
  }
}
