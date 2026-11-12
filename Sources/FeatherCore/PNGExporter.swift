import CoreGraphics
import Darwin
import Foundation

public enum ExportError: Error, LocalizedError {
  case renderFailed
  case invalidPNG
  case invalidDirectory
  case invalidFilename

  public var errorDescription: String? {
    switch self {
    case .renderFailed: "The screenshot could not be rendered."
    case .invalidPNG: "The image is not a valid PNG."
    case .invalidFilename: "The filename template is invalid."
    case .invalidDirectory: "The selected save location is not a directory."
    }
  }
}

/// 仅在用户触发保存时写文件，无网络和后台任务。
public enum PNGExporter {
  /// 校验 PNG 签名并原子写入唯一文件名；不覆盖已有截图，磁盘与权限错误原样抛出。
  public static func save(
    _ data: Data, to directory: URL, now: Date = Date(),
    template: String = FilenameTemplate.defaultValue, imageSize: CGSize = .zero
  ) throws -> URL {
    guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw ExportError.invalidPNG }
    let name = try FilenameTemplate.filename(template: template, now: now, size: imageSize)
    let stem = String(name.dropLast(4))
    let manager = FileManager.default
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
      guard isDirectory.boolValue else { throw ExportError.invalidDirectory }
    } else {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    // Foundation 不支持 atomic 与 withoutOverwriting 组合，使用同目录暂存和独占重命名。
    let staging = directory.appendingPathComponent(".feather-\(UUID().uuidString).tmp")
    defer { try? manager.removeItem(at: staging) }
    try data.write(to: staging, options: .atomic)
    for suffix in 0..<1000 {
      let filename = suffix == 0 ? name : "\(stem)-\(suffix).png"
      let url = directory.appendingPathComponent(filename)
      if renamex_np(staging.path, url.path, UInt32(RENAME_EXCL)) == 0 { return url }
      guard errno == EEXIST else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
    throw NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST))
  }
}
