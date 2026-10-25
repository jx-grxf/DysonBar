import DysonKit
import SwiftUI

struct PanelView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let device = model.store.selected {
        DevicePanel(device: device)
          .id(device.id)
          .transition(.opacity)
      } else {
        EmptyPanel(missing: model.store.missingPasswords.first)
      }
    }
    .padding(Tokens.padding)
    .frame(width: Tokens.panelWidth)
    .fixedSize(horizontal: false, vertical: true)
    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
      window.fit(contentHeight: height)
    }
    .background(WindowReader(window: window))
    .frame(maxHeight: .infinity, alignment: .top)
    .animation(reduceMotion ? nil : Tokens.switchMotion, value: model.store.selected?.id)
  }

  @State private var window = PanelWindow()
}

/// `MenuBarExtra` grows its window when the content gets taller but never
/// shrinks it again, so closing the history chart left empty space around the
/// panel. The window is sized to the content here instead, top edge pinned
/// under the menu bar.
@MainActor
final class PanelWindow {
  weak var window: NSWindow?
  private var pendingHeight: CGFloat?

  func fit(contentHeight: CGFloat) {
    guard let window else {
      pendingHeight = contentHeight
      return
    }
    // Window frames snap to whole points; fractional heights mid-animation
    // would otherwise resize the window again on every layout pass.
    let height = contentHeight.rounded(.up)
    let content = window.contentRect(forFrameRect: window.frame)
    guard abs(content.height - height) >= 1 else { return }
    var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.minY, width: content.width, height: height))
    frame.origin.y = window.frame.maxY - frame.height
    window.setFrame(frame, display: true, animate: false)
  }

  fileprivate func attach(_ window: NSWindow) {
    guard self.window !== window else { return }
    self.window = window
    if let pendingHeight {
      self.pendingHeight = nil
      fit(contentHeight: pendingHeight)
    }
  }
}

private struct WindowReader: NSViewRepresentable {
  let window: PanelWindow

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async { [weak view] in
      if let found = view?.window { window.attach(found) }
    }
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    if let found = view.window { window.attach(found) }
  }
}

private struct DevicePanel: View {
  let device: DysonDevice

  @State private var chartMetric: Metric?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Header(device: device)

      if device.snapshot.hasData {
        DeviceDisplay(device: device, chartMetric: $chartMetric)
        SensorRow(device: device, selection: $chartMetric)

        if let metric = chartMetric {
          HistoryCard(device: device, metric: metric) { chartMetric = nil }
            .transition(.asymmetric(
              insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
              removal: .opacity))
        }

        DeviceControls(device: device)
          .disabled(!device.connection.isConnected)
          .opacity(device.connection.isConnected ? 1 : 0.55)
      } else {
        ConnectionPlaceholder(device: device)
      }

      Footer(device: device)
    }
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: chartMetric)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: device.snapshot.hasData)
  }
}

// MARK: - Header

private struct Header: View {
  let device: DysonDevice
  @Environment(AppModel.self) private var model

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        DeviceSwitcher(device: device)
        StatusLine(device: device)
      }

      Spacer()

      Button { device.setPower(!device.snapshot.isOn) } label: {
        Image(systemName: "power")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(device.snapshot.isOn ? Color.white : Color.primary)
          .frame(width: 38, height: 38)
          .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .controlSurface(active: device.snapshot.isOn, shape: .circle)
      .disabled(!device.connection.isConnected)
      .keyboardShortcut("p", modifiers: [])
      .help(device.snapshot.isOn ? String(localized: "Turn off (P)") : String(localized: "Turn on (P)"))
      .accessibilityLabel(device.snapshot.isOn ? String(localized: "Turn off") : String(localized: "Turn on"))
    }
    .padding(.horizontal, 4)
  }
}

private struct DeviceSwitcher: View {
  let device: DysonDevice
  @Environment(AppModel.self) private var model

  var body: some View {
    let devices = model.store.devices
    if devices.count > 1 {
      Menu {
        ForEach(devices) { other in
          Button {
            model.store.selectedID = other.id
          } label: {
            if other.id == device.id {
              Label(other.name, systemImage: "checkmark")
            } else {
              Text(other.name)
            }
          }
        }
        Divider()
        Button(String(localized: "Manage Devices…")) { WindowPresenter.showSettings(tab: .devices) }
      } label: {
        HStack(spacing: 4) {
          title
          Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
      }
      .menuStyle(.button)
      .buttonStyle(.plain)
      .menuIndicator(.hidden)
      .fixedSize()
      .help(String(localized: "Switch device"))
    } else {
      title
    }
  }

  private var title: some View {
    Text(device.name)
      .font(.system(size: 17, weight: .semibold))
      .lineLimit(1)
  }
}

private struct StatusLine: View {
  let device: DysonDevice

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let (symbol, text, tint) = describe(now: context.date)
      HStack(spacing: 5) {
        if let symbol {
          Image(systemName: symbol).foregroundStyle(tint)
        }
        Text(text).lineLimit(1)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .contentTransition(.interpolate)
    }
  }

  private func describe(now: Date) -> (String?, String, Color) {
    let product = device.record.productName
    switch device.connection {
    case .connected:
      let snapshot = device.snapshot
      let mode =
        !snapshot.isOn
        ? String(localized: "Off")
        : snapshot.isFanRunning ? String(localized: "Running") : String(localized: "Standby")
      if !snapshot.faults.isEmpty || snapshot.warningCode != nil {
        return ("exclamationmark.triangle.fill", "\(product) · \(String(localized: "Check device"))", Tokens.level(.poor))
      }
      return (nil, "\(product) · \(mode)", .secondary)
    case .searching:
      return ("magnifyingglass", String(localized: "Searching the network …"), .secondary)
    case .connecting:
      return ("arrow.triangle.2.circlepath", String(localized: "Connecting …"), .secondary)
    case .offline:
      if let last = device.snapshot.lastUpdate {
        let age = last.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        return ("wifi.exclamationmark", String(localized: "Offline · values from \(age)"), Tokens.level(.poor))
      }
      return ("wifi.exclamationmark", String(localized: "Not reachable"), Tokens.level(.poor))
    }
  }
}

// MARK: - Placeholders

private struct ConnectionPlaceholder: View {
  let device: DysonDevice

  var body: some View {
    VStack(spacing: 10) {
      switch device.connection {
      case .searching, .connecting, .connected:
        ProgressView().controlSize(.small)
        Text("Connecting to \(device.name) …")
          .font(.callout)
          .foregroundStyle(.secondary)
      case .offline(let reason):
        Image(systemName: "wifi.exclamationmark")
          .font(.system(size: 26))
          .foregroundStyle(.secondary)
        Text("\(device.name) isn't answering")
          .font(.headline)
        Text("Is the purifier plugged in and on the same Wi-Fi as this Mac? (\(reason))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
        HStack {
          Button("Try Again") { device.reconnect() }
          Button("Set Address…") { WindowPresenter.showSettings(tab: .devices) }
        }
        .controlSize(.small)
      }
    }
    .padding(.horizontal, 20)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
    .background(Tokens.cardFill, in: .rect(cornerRadius: Tokens.displayRadius, style: .continuous))
  }
}

private struct EmptyPanel: View {
  let missing: DeviceRecord?

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: missing == nil ? "air.purifier" : "key.fill")
        .font(.system(size: 30))
        .foregroundStyle(.secondary)
      Text(missing == nil ? "No purifier set up yet" : "Sign in again")
        .font(.headline)
      Text(
        missing == nil
          ? "Sign in with your MyDyson account once. After that DysonBar talks to the purifier directly over Wi-Fi."
          : "The Keychain entry for \(missing?.displayName ?? "") is missing. Sign in once more to restore it."
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      Button("Set Up…") { WindowPresenter.showOnboarding() }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
      HStack {
        Spacer()
        QuitButton()
      }
    }
    .padding(.horizontal, 12)
    .padding(.top, 24)
  }
}

// MARK: - Footer

private struct Footer: View {
  let device: DysonDevice

  var body: some View {
    HStack(spacing: 12) {
      if let hepa = device.snapshot.hepaFilter {
        FilterGauge(title: String(localized: "HEPA"), percent: hepa)
      }
      if let carbon = device.snapshot.carbonFilter {
        FilterGauge(title: String(localized: "Carbon"), percent: carbon)
      }

      Spacer()

      if case .connected(let address) = device.connection {
        Label("Local", systemImage: "wifi")
          .foregroundStyle(.tertiary)
          .help(String(localized: "Connected directly over Wi-Fi (\(address)), without the Dyson cloud"))
      }

      FooterButton(symbol: "arrow.clockwise", help: String(localized: "Refresh (⌘R)")) {
        device.requestEverything()
      }
      .keyboardShortcut("r")
      .disabled(!device.connection.isConnected)

      FooterButton(symbol: "gearshape", help: String(localized: "Settings (⌘,)")) {
        WindowPresenter.showSettings()
      }
      .keyboardShortcut(",")

      QuitButton()
    }
    .font(.caption)
    .padding(.horizontal, 4)
  }
}

private struct FilterGauge: View {
  let title: String
  let percent: Int

  var body: some View {
    HStack(spacing: 6) {
      Text(title)
        .foregroundStyle(.secondary)
      Capsule()
        .fill(Tokens.track)
        .frame(width: 30, height: 4)
        .overlay(alignment: .leading) {
          Capsule()
            .fill(tint)
            .frame(width: 30 * CGFloat(min(max(percent, 0), 100)) / 100)
        }
      Text("\(percent) %")
        .monospacedDigit()
        .foregroundStyle(percent <= 15 ? tint : .secondary)
    }
    .help(percent <= 15 ? String(localized: "Replace the \(title) filter soon") : String(localized: "\(title) filter: \(percent) % left"))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "\(title) filter"))
    .accessibilityValue(String(localized: "\(percent) percent"))
  }

  private var tint: Color {
    switch percent {
    case ...5: Tokens.level(.veryPoor)
    case ...15: Tokens.level(.poor)
    default: Color.primary.opacity(0.45)
    }
  }
}

private struct FooterButton: View {
  let symbol: String
  let help: String
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .frame(width: 24, height: 24)
        .background(hovering ? Tokens.hover : .clear, in: .circle)
        .contentShape(.circle)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .onHover { hovering = $0 }
    .animation(Tokens.hoverMotion, value: hovering)
    .help(help)
    .accessibilityLabel(help)
  }
}

private struct QuitButton: View {
  var body: some View {
    FooterButton(symbol: "power.circle", help: String(localized: "Quit DysonBar (⌘Q)")) {
      NSApp.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
