import CoreGraphics
import Foundation

/// 安全文件名模板；只接受明确占位符及单个文件名，拒绝目录穿越和未知变量。
public enum FilenameTemplate {
  public static let defaultValue = "Feather_{date}_{time}_{uuid}"
  public static let tokens = ["date", "time", "timestamp", "uuid", "width", "height"]

  /// 校验模板并返回去除首尾空白的形式；非法字符、变量或长度抛出稳定英文内核错误。
  public static func validated(_ template: String) throws -> String {
    let value = template.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !value.hasPrefix("."), value.utf8.count <= 160,
      value.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
        == nil
    else { throw ExportError.invalidFilename }
    var remaining = value
    for token in tokens { remaining = remaining.replacingOccurrences(of: "{\(token)}", with: "") }
    guard !remaining.contains("{"), !remaining.contains("}") else {
      throw ExportError.invalidFilename
    }
    return value
  }

  /// 展开为 PNG 文件名；日期使用本地时区，随机标识由调用方提供，碰撞由导出器独占处理。
  public static func filename(
    template: String, now: Date = Date(), size: CGSize = .zero,
    identifier: String = String(UUID().uuidString.prefix(8))
  ) throws -> String {
    guard size.width.isFinite, size.height.isFinite, size.width >= 0, size.height >= 0,
      size.width < CGFloat(Int.max), size.height < CGFloat(Int.max),
      now.timeIntervalSince1970.isFinite,
      abs(now.timeIntervalSince1970 * 1000) < Double(Int64.max)
    else { throw ExportError.invalidFilename }
    var value = try validated(template)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let date = formatter.string(from: now)
    formatter.dateFormat = "HH-mm-ss-SSS"
    let replacements = [
      "date": date, "time": formatter.string(from: now),
      "timestamp": String(Int64(now.timeIntervalSince1970 * 1000)), "uuid": identifier,
      "width": String(Int(size.width)), "height": String(Int(size.height)),
    ]
    for (token, replacement) in replacements {
      value = value.replacingOccurrences(of: "{\(token)}", with: replacement)
    }
    if value.lowercased().hasSuffix(".png") { value.removeLast(4) }
    guard !value.isEmpty, !value.hasPrefix("."), value.utf8.count <= 220,
      value.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\").union(.controlCharacters))
        == nil
    else { throw ExportError.invalidFilename }
    return value + ".png"
  }
}
