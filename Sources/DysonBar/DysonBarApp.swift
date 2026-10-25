import SwiftUI

@main
struct DysonBarApp: App {
  @State private var device = DysonDevice()

  var body: some Scene {
    MenuBarExtra {
      PanelView(device: device)
    } label: {
      MenuBarLabel(device: device)
    }
    .menuBarExtraStyle(.window)
  }
}

private struct MenuBarLabel: View {
  let device: DysonDevice
  @State private var started = false

  var body: some View {
    Image(systemName: device.isOn ? "air.purifier.fill" : "air.purifier")
      .opacity(device.connection.isConnected ? 1 : 0.45)
      .accessibilityLabel("DysonBar")
      .task {
        // The label is the only view alive from launch on, so it kicks off the connection.
        guard !started else { return }
        started = true
        device.start()
        await renderSnapshotIfRequested()
      }
  }

  /// `--snapshot <path> [light|dark]` writes the panel with live data to a PNG and quits,
  /// so layout changes can be checked without clicking the menu bar.
  private func renderSnapshotIfRequested() async {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return }
    let scheme: ColorScheme = arguments.dropFirst(index + 2).first == "light" ? .light : .dark
    try? await Task.sleep(for: .seconds(4))
    let panel = PanelView(device: device)
      .background(scheme == .dark ? Color(white: 0.14) : Color(white: 0.95))
      .environment(\.colorScheme, scheme)
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
