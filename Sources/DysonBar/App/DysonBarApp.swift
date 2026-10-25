import AppKit
import DysonKit
import SwiftUI

@main
struct DysonBarApp: App {
  @NSApplicationDelegateAdaptor private var delegate: AppDelegate
  @State private var model = AppModel.shared

  var body: some Scene {
    MenuBarExtra {
      PanelView()
        .environment(model)
    } label: {
      MenuBarLabel()
        .environment(model)
    }
    .menuBarExtraStyle(.window)
  }
}

private struct MenuBarLabel: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let device = model.store.selected
    let snapshot = device?.snapshot
    let connected = device?.connection.isConnected ?? false
    let symbol = snapshot?.isOn == true ? "air.purifier.fill" : "air.purifier"

    Group {
      switch model.preferences.menuBarStyle {
      case .icon:
        Image(systemName: symbol)
      case .status:
        Image(nsImage: StatusIcon.image(symbol: symbol, dot: connected ? snapshot?.worstReading?.level : nil))
      case .level:
        Label(snapshot?.worstReading?.level.title ?? "–", systemImage: symbol)
          .labelStyle(.titleAndIcon)
      case .temperature:
        Label(
          snapshot?.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" } ?? "–",
          systemImage: symbol
        )
        .labelStyle(.titleAndIcon)
      }
    }
    .opacity(connected ? 1 : 0.5)
    .accessibilityLabel(accessibilityText(device))
    .task {
      // The label is the only view alive from launch on, so it starts everything.
      model.start()
      await Snapshot.renderIfRequested(model: model)
    }
  }

  private func accessibilityText(_ device: DysonDevice?) -> String {
    guard let device, let level = device.snapshot.worstReading?.level else { return "DysonBar" }
    return String(localized: "DysonBar, air quality \(level.title)")
  }
}

/// The menu bar draws template images in its own colour, which would also
/// grey out the dot. This image draws the symbol in the label colour at draw
/// time, so it still follows a light or dark menu bar, and keeps the dot coloured.
enum StatusIcon {
  static func image(symbol: String, dot level: AirLevel?) -> NSImage {
    let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
      .withSymbolConfiguration(configuration)
    else { return NSImage() }
    guard let level else {
      base.isTemplate = true
      return base
    }
    let dotSize: CGFloat = 6
    let size = NSSize(width: base.size.width + 3, height: max(base.size.height, 16))
    let color = NSColor(level.color)
    let image = NSImage(size: size, flipped: false) { rect in
      let glyph = NSRect(
        x: 0, y: (rect.height - base.size.height) / 2, width: base.size.width, height: base.size.height)
      base.draw(in: glyph)
      NSColor.labelColor.set()
      glyph.fill(using: .sourceAtop)
      // Punch a ring around the dot so it reads on the glyph.
      let dot = NSRect(x: rect.width - dotSize, y: rect.minY + 1, width: dotSize, height: dotSize)
      NSGraphicsContext.current?.compositingOperation = .clear
      NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
      NSGraphicsContext.current?.compositingOperation = .sourceOver
      color.set()
      NSBezierPath(ovalIn: dot).fill()
      return true
    }
    image.isTemplate = false
    return image
  }
}

/// `--snapshot <path> [light|dark]` writes the panel with live data to a PNG and
/// quits, so layout changes and README screenshots don't need a click on the menu bar.
/// `--frames <dir> [light|dark]` writes three seconds of PNG frames for the README GIF.
@MainActor
enum Snapshot {
  static func renderIfRequested(model: AppModel) async {
    let arguments = ProcessInfo.processInfo.arguments
    let still = arguments.firstIndex(of: "--snapshot")
    let frames = arguments.firstIndex(of: "--frames")
    guard let index = still ?? frames, index + 1 < arguments.count else { return }
    let target = URL(fileURLWithPath: arguments[index + 1])
    let scheme: ColorScheme = arguments.dropFirst(index + 2).first == "light" ? .light : .dark
    try? await Task.sleep(for: .seconds(5))

    if still != nil {
      write(render(model: model, scheme: scheme, progress: 1), to: target)
    } else {
      try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
      let count = 60
      for frame in 0..<count {
        // The ring sweeps in over the first second, then the air keeps moving.
        let t = min(Double(frame) / 20, 1)
        let eased = 1 - pow(1 - t, 3)
        let image = render(model: model, scheme: scheme, progress: eased)
        write(image, to: target.appending(path: String(format: "frame-%03d.png", frame)))
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
    NSApp.terminate(nil)
  }

  private static func render(model: AppModel, scheme: ColorScheme, progress: Double) -> NSImage? {
    let panel = PanelView()
      .environment(model)
      .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.96))
      .clipShape(.rect(cornerRadius: 18, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(scheme == .dark ? 0.1 : 0)))
      .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
      .padding(36)
      .background(
        LinearGradient(
          colors: scheme == .dark
            ? [Color(red: 0.11, green: 0.14, blue: 0.19), Color(red: 0.05, green: 0.06, blue: 0.08)]
            : [Color(red: 0.86, green: 0.90, blue: 0.95), Color(red: 0.95, green: 0.96, blue: 0.98)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .environment(\.colorScheme, scheme)
      .environment(\.isSnapshot, true)
      .environment(\.snapshotProgress, progress)
    let renderer = ImageRenderer(content: panel)
    renderer.scale = 2
    return renderer.nsImage
  }

  private static func write(_ image: NSImage?, to url: URL) {
    guard let tiff = image?.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else { return }
    try? png.write(to: url)
  }
}
