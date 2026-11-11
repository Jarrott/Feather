import AppKit

// 构建时绘制原生矢量图标，不依赖网络或外部图像资源。
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
  for scale in [1, 2] {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    let factor = CGFloat(pixels) / 1024
    context.scaleBy(x: factor, y: factor)
    NSColor(srgbRed: 0.10, green: 0.19, blue: 0.16, alpha: 1).setFill()
    NSBezierPath(
      roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 215, yRadius: 215
    ).fill()
    NSColor(srgbRed: 0.70, green: 0.95, blue: 0.83, alpha: 1).setStroke()
    let crop = NSBezierPath()
    crop.lineWidth = 55
    crop.lineCapStyle = .round
    crop.lineJoinStyle = .round
    for (x, y, dx, dy) in [
      (275.0, 275.0, 1.0, 1.0), (749, 275, -1, 1), (275, 749, 1, -1), (749, 749, -1, -1),
    ] {
      crop.move(to: CGPoint(x: x, y: y + 130 * dy))
      crop.line(to: CGPoint(x: x, y: y))
      crop.line(to: CGPoint(x: x + 130 * dx, y: y))
    }
    crop.stroke()
    let feather = NSBezierPath()
    feather.move(to: CGPoint(x: 425, y: 390))
    feather.curve(
      to: CGPoint(x: 628, y: 659), controlPoint1: CGPoint(x: 400, y: 570),
      controlPoint2: CGPoint(x: 515, y: 665))
    feather.curve(
      to: CGPoint(x: 425, y: 390), controlPoint1: CGPoint(x: 645, y: 520),
      controlPoint2: CGPoint(x: 548, y: 408))
    NSColor(srgbRed: 0.70, green: 0.95, blue: 0.83, alpha: 1).setFill()
    feather.fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let suffix = scale == 2 ? "@2x" : ""
    try bitmap.representation(using: .png, properties: [:])!.write(
      to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
  }
}
