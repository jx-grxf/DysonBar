// Builds AppIcon.icns from the 1024 px Icon Composer render: the macOS icon
// grid (824 pt squircle in a 1024 canvas) with the system drop shadow. actool
// only emits up to 256 px, which looks soft in Finder before macOS 26.
import AppKit

let args = CommandLine.arguments
let source = NSImage(contentsOfFile: args[1])!
let iconset = URL(fileURLWithPath: args[2])
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ size: Int) -> Data {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let scale = CGFloat(size) / 1024
  let body = NSRect(x: 100, y: 100, width: 824, height: 824)
  let transform = NSAffineTransform()
  transform.scale(by: scale)
  transform.concat()
  let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow()
  shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
  shadow.shadowBlurRadius = 20
  shadow.shadowOffset = NSSize(width: 0, height: -10)
  shadow.set()
  NSColor.black.setFill()
  path.fill()
  NSGraphicsContext.restoreGraphicsState()
  path.addClip()
  source.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
  try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
  try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
