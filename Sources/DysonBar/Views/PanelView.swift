import SwiftUI

struct PanelView: View {
  let device: DysonDevice

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Header(device: device)

      if device.hasData {
        HeroDisplay(device: device)
        SensorStrip(readings: device.readings)
          .padding(.horizontal, 4)

        VStack(spacing: 16) {
          FanControl(device: device)
          FeatureRow(device: device)
          if device.isOscillating {
            OscillationWidthPicker(selected: device.oscillationWidth) { device.setOscillationWidth($0) }
              .transition(.opacity.combined(with: .move(edge: .top)))
          }
        }
        .disabled(!device.connection.isConnected)
      } else {
        ConnectionPlaceholder(device: device)
      }

      Footer(device: device)
    }
    .padding(Tokens.padding)
    .frame(width: Tokens.panelWidth)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: device.isOscillating)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: device.hasData)
  }
}

private struct Header: View {
  let device: DysonDevice

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(device.name)
          .font(.system(size: 17, weight: .semibold))
        StatusLine(device: device)
      }

      Spacer()

      Button { device.setPower(!device.isOn) } label: {
        Image(systemName: "power")
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(device.isOn ? Color.white : Color.primary)
          .frame(width: 36, height: 36)
          .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .controlSurface(active: device.isOn, shape: .circle)
      .disabled(!device.connection.isConnected)
      .keyboardShortcut("p", modifiers: [])
      .help(device.isOn ? "Ausschalten (P)" : "Einschalten (P)")
      .accessibilityLabel(device.isOn ? "Ausschalten" : "Einschalten")
    }
    .padding(.horizontal, 4)
  }
}

private struct StatusLine: View {
  let device: DysonDevice

  var body: some View {
    let (symbol, text, tint) = describe()
    HStack(spacing: 5) {
      if let symbol {
        Image(systemName: symbol).foregroundStyle(tint)
      }
      Text(text).lineLimit(1)
    }
    .font(.caption)
    .foregroundStyle(.secondary)
  }

  private func describe() -> (String?, String, Color) {
    let product = device.config?.productName ?? "Dyson"
    switch device.connection {
    case .connected:
      let mode = device.isOn ? (device.isFanRunning ? "Läuft" : "Bereit") : "Aus"
      return (nil, "\(product) · \(mode)", .secondary)
    case .searching:
      return ("magnifyingglass", "Suche im Netzwerk …", .secondary)
    case .connecting:
      return ("arrow.triangle.2.circlepath", "Verbinde …", .secondary)
    case .offline:
      return ("wifi.exclamationmark", "Nicht erreichbar", Tokens.level(.poor))
    case .setupMissing:
      return ("exclamationmark.triangle.fill", "Nicht eingerichtet", Tokens.level(.poor))
    }
  }
}

private struct ConnectionPlaceholder: View {
  let device: DysonDevice

  var body: some View {
    VStack(spacing: 10) {
      switch device.connection {
      case .searching, .connecting, .connected:
        ProgressView().controlSize(.small)
        Text("Verbinde mit \(device.name) …")
          .font(.callout)
          .foregroundStyle(.secondary)
      case .offline(let reason):
        Image(systemName: "wifi.exclamationmark")
          .font(.system(size: 26))
          .foregroundStyle(.secondary)
        Text("\(device.name) antwortet nicht")
          .font(.headline)
        Text("Ist der Luftreiniger eingesteckt und im selben WLAN? (\(reason))")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Erneut versuchen") { device.reconnect() }
          .controlSize(.small)
      case .setupMissing(let message):
        Image(systemName: "key.fill")
          .font(.system(size: 26))
          .foregroundStyle(.secondary)
        Text("Gerät einrichten")
          .font(.headline)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        Button("Erneut laden") { device.reconnect() }
          .controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 36)
    .background(Tokens.cardFill, in: .rect(cornerRadius: 20, style: .continuous))
  }
}

private struct Footer: View {
  let device: DysonDevice

  var body: some View {
    HStack(spacing: 10) {
      if let filter = device.filterLife {
        HStack(spacing: 6) {
          Text("Filter")
            .foregroundStyle(.secondary)
          Capsule()
            .fill(Tokens.track)
            .frame(width: 36, height: 4)
            .overlay(alignment: .leading) {
              Capsule()
                .fill(filterTint(filter))
                .frame(width: 36 * CGFloat(filter) / 100)
            }
          Text("\(filter) %")
            .monospacedDigit()
            .foregroundStyle(filter <= 15 ? filterTint(filter) : .secondary)
        }
        .help(filter <= 15 ? "HEPA-Filter bald tauschen" : "HEPA-Filter: noch \(filter) %")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Filter")
        .accessibilityValue("\(filter) Prozent")
      }

      Spacer()

      if case .connected(let address) = device.connection {
        Label("Lokal", systemImage: "wifi")
          .foregroundStyle(.tertiary)
          .help("Direkt im WLAN verbunden (\(address)), ohne Dyson-Cloud")
      }

      Button { device.requestEverything() } label: {
        Image(systemName: "arrow.clockwise")
          .frame(width: 22, height: 22)
          .contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("r")
      .help("Aktualisieren (⌘R)")
      .accessibilityLabel("Aktualisieren")
      .disabled(!device.connection.isConnected)

      Button { NSApp.terminate(nil) } label: {
        Image(systemName: "power.circle")
          .frame(width: 22, height: 22)
          .contentShape(.rect)
      }
      .buttonStyle(.borderless)
      .keyboardShortcut("q")
      .help("DysonBar beenden (⌘Q)")
      .accessibilityLabel("DysonBar beenden")
    }
    .font(.caption)
    .padding(.horizontal, 4)
  }

  private func filterTint(_ percent: Int) -> Color {
    switch percent {
    case ...5: Tokens.level(.veryPoor)
    case ...15: Tokens.level(.poor)
    default: Color.primary.opacity(0.45)
    }
  }
}
