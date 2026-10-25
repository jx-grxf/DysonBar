import AppKit
import DysonKit
import SwiftUI

@main
struct DysonBarApp: App {
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
@MainActor
enum Snapshot {
  static func renderIfRequested(model: AppModel) async {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
    let scheme: ColorScheme = arguments.dropFirst(index + 2).first == "light" ? .light : .dark
    try? await Task.sleep(for: .seconds(5))
    let panel = PanelView()
      .environment(model)
      .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.96))
      .environment(\.colorScheme, scheme)
      .environment(\.isSnapshot, true)
    let renderer = ImageRenderer(content: panel)
    renderer.scale = 2
    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
      let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    {
      try? png.write(to: URL(fileURLWithPath: arguments[index + 1]))
    }
    NSApp.terminate(nil)
  }
}
