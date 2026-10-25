import SwiftUI

struct SensorStrip: View {
  let readings: [Reading]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(readings) { reading in
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 5) {
            Circle()
              .fill(reading.level.color)
              .frame(width: 6, height: 6)
            Text(reading.pollutant.title)
              .font(.caption2.weight(.medium))
              .foregroundStyle(.secondary)
          }
          Text(reading.pollutant.format(reading.value))
            .font(.system(.callout, design: .rounded, weight: .semibold).monospacedDigit())
            .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(reading.pollutant.longTitle): \(reading.pollutant.format(reading.value)) \(reading.pollutant.unit), \(reading.level.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.pollutant.longTitle)
        .accessibilityValue("\(reading.pollutant.format(reading.value)) \(reading.pollutant.unit), \(reading.level.title)")
      }
    }
    .animation(Tokens.dataMotion, value: readings.map(\.value))
  }
}

struct FanControl: View {
  let device: DysonDevice

  var body: some View {
    HStack(spacing: 8) {
      Button { device.setAuto(!device.isAuto) } label: {
        Text("Auto")
          .font(.callout.weight(.semibold))
          .foregroundStyle(device.isOn && device.isAuto ? Color.white : Color.primary)
          .frame(width: 60, height: 42)
          .contentShape(.capsule)
      }
      .buttonStyle(.plain)
      .controlSurface(active: device.isOn && device.isAuto, shape: .capsule)
      .help("Stufe passt sich der Luftqualität an")
      .accessibilityAddTraits(device.isOn && device.isAuto ? .isSelected : [])

      FanSlider(
        speed: device.isOn && !device.isAuto ? device.fanSpeed : nil,
        isRunning: device.isFanRunning,
        isAuto: device.isOn && device.isAuto,
        onChange: { device.setSpeed($0) }
      )
    }
  }
}

/// Control Center style: a thick capsule that fills to the chosen step.
private struct FanSlider: View {
  let speed: Int?
  let isRunning: Bool
  let isAuto: Bool
  let onChange: (Int) -> Void

  @State private var dragStep: Int?
  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var shown: Int { dragStep ?? speed ?? 0 }

  private var title: String {
    if let dragStep { return "Stufe \(dragStep)" }
    if isAuto { return "Automatisch" }
    return speed.map { "Stufe \($0)" } ?? "Aus"
  }

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let fill = shown == 0 ? 0 : max(42, width * CGFloat(shown) / 10)

      ZStack(alignment: .leading) {
        Capsule().fill(hovering ? Tokens.track.opacity(1.5) : Tokens.track)

        Capsule()
          .fill(Color.accentColor)
          .frame(width: fill)

        label.foregroundStyle(.primary)
        label
          .foregroundStyle(.white)
          .mask(alignment: .leading) { Rectangle().frame(width: fill) }
      }
      .contentShape(.capsule)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { dragStep = step(at: $0.location.x, width: width) }
          .onEnded {
            let step = step(at: $0.location.x, width: width)
            dragStep = nil
            onChange(step)
          }
      )
      .onHover { hovering = $0 }
    }
    .frame(height: 42)
    .animation(reduceMotion ? nil : Tokens.hoverMotion, value: shown)
    .accessibilityElement()
    .accessibilityLabel("Lüfterstufe")
    .accessibilityValue(title)
    .accessibilityAdjustableAction { direction in
      let current = speed ?? 1
      onChange(direction == .increment ? min(current + 1, 10) : max(current - 1, 1))
    }
  }

  private var label: some View {
    HStack(spacing: 8) {
      Image(systemName: "fan.fill")
        .font(.system(size: 14, weight: .semibold))
        .symbolEffect(.rotate, options: .speed(Double(max(shown, 3)) / 5), isActive: isRunning && !reduceMotion)
      Text(title)
        .font(.callout.weight(.semibold).monospacedDigit())
        .contentTransition(.numericText())
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14)
  }

  private func step(at x: CGFloat, width: CGFloat) -> Int {
    min(max(Int(ceil(x / max(width, 1) * 10)), 1), 10)
  }
}

struct FeatureRow: View {
  let device: DysonDevice

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      RoundToggle(
        title: "Schwenken",
        detail: device.isOscillating ? device.oscillationWidth.map { "\($0)°" } ?? "An" : "Aus",
        symbol: "fan.oscillation.fill",
        isActive: device.isOscillating
      ) { device.setOscillation(!device.isOscillating) }

      RoundToggle(
        title: "Nacht",
        detail: device.isNightMode ? "Leise" : "Aus",
        symbol: "moon.zzz.fill",
        isActive: device.isNightMode
      ) { device.setNightMode(!device.isNightMode) }

      RoundToggle(
        title: device.airflow == .front ? "Kühlen" : "Diffus",
        detail: device.airflow == .front ? "Nach vorne" : "Nach hinten",
        symbol: device.airflow == .front ? "wind" : "arrow.uturn.backward",
        isActive: device.airflow == .front
      ) { device.setAirflow(device.airflow == .front ? .back : .front) }

      SleepTimerToggle(device: device)
    }
  }
}

private struct RoundToggle: View {
  let title: String
  let detail: String
  let symbol: String
  let isActive: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ToggleFace(title: title, detail: detail, symbol: symbol, isActive: isActive)
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(title)
    .accessibilityValue(detail)
    .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
  }
}

private struct ToggleFace: View {
  let title: String
  let detail: String
  let symbol: String
  let isActive: Bool

  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: 50, height: 50)
        .controlSurface(active: isActive, shape: .circle)
        .scaleEffect(hovering ? 1.05 : 1)
      VStack(spacing: 1) {
        Text(title)
          .font(.caption.weight(.semibold))
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .contentTransition(.interpolate)
      }
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
    .contentShape(.rect)
    .onHover { hovering = $0 }
    .animation(reduceMotion ? nil : Tokens.hoverMotion, value: hovering)
    .animation(reduceMotion ? nil : Tokens.hoverMotion, value: isActive)
  }
}

private struct SleepTimerToggle: View {
  let device: DysonDevice

  var body: some View {
    Menu {
      Section("Ausschalten in") {
        ForEach(DysonDevice.sleepTimerMinutes, id: \.self) { minutes in
          Button(Self.format(minutes)) { device.setSleepTimer(minutes) }
        }
      }
      if device.sleepTimer != nil {
        Button("Timer beenden") { device.setSleepTimer(nil) }
      }
    } label: {
      ToggleFace(
        title: "Timer",
        detail: device.sleepTimer.map { Self.format($0) } ?? "Aus",
        symbol: "timer",
        isActive: device.sleepTimer != nil
      )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .frame(maxWidth: .infinity)
    .accessibilityLabel("Ausschalt-Timer")
  }

  static func format(_ minutes: Int) -> String {
    let hours = minutes / 60
    let rest = minutes % 60
    switch (hours, rest) {
    case (0, _): return "\(rest) min"
    case (_, 0): return "\(hours) h"
    default: return "\(hours) h \(rest) min"
    }
  }
}

struct OscillationWidthPicker: View {
  let selected: Int?
  let onSelect: (Int) -> Void

  @Namespace private var selection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(DysonDevice.oscillationWidths, id: \.self) { width in
        let isSelected = closest == width
        Button { onSelect(width) } label: {
          Text("\(width)°")
            .font(.caption.weight(isSelected ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
              if isSelected {
                Capsule()
                  .fill(Color(nsColor: .controlBackgroundColor))
                  .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                  .matchedGeometryEffect(id: "selection", in: selection)
              }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
      }
    }
    .padding(3)
    .background(Tokens.track, in: .capsule)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: closest)
    .accessibilityLabel("Schwenkbereich")
  }

  /// The device may report e.g. 180° as 97…277, so snap to the nearest preset.
  private var closest: Int? {
    guard let selected else { return nil }
    return DysonDevice.oscillationWidths.min { abs($0 - selected) < abs($1 - selected) }
  }
}
