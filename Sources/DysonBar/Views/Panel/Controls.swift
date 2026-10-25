import DysonKit
import SwiftUI

/// Only what the device reports gets a control, so heaters, humidifiers and
/// plain purifiers each see their own set.
struct DeviceControls: View {
  let device: DysonDevice
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let snapshot = device.snapshot
    let caps = snapshot.capabilities
    VStack(spacing: 14) {
      FanControl(device: device)
      FeatureGrid(device: device)

      if caps.contains(.oscillationAngles), snapshot.isOscillating {
        SegmentedChoice(
          options: DysonDevice.oscillationWidths,
          selected: snapshot.oscillationWidth.map { width in
            DysonDevice.oscillationWidths.min { abs($0 - width) < abs($1 - width) }!
          },
          label: { "\($0)°" },
          accessibilityLabel: String(localized: "Oscillation range")
        ) { device.setOscillationWidth($0) }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if caps.contains(.heating), snapshot.isHeating {
        HeatingTarget(device: device)
          .transition(.opacity.combined(with: .move(edge: .top)))
      }

      if caps.contains(.humidifier), snapshot.isHumidifying {
        SegmentedChoice(
          options: [0] + DysonDevice.humidityTargets,
          selected: snapshot.isHumidityAuto ? 0 : snapshot.humidityTarget,
          label: { $0 == 0 ? String(localized: "Auto") : "\($0) %" },
          accessibilityLabel: String(localized: "Target humidity")
        ) { value in
          value == 0 ? device.setHumidityAuto(true) : device.setHumidityTarget(value)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: snapshot.isOscillating)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: snapshot.isHeating)
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: snapshot.isHumidifying)
  }
}

private struct FanControl: View {
  let device: DysonDevice

  var body: some View {
    let snapshot = device.snapshot
    HStack(spacing: 8) {
      if snapshot.capabilities.contains(.auto) {
        Button { device.setAuto(!snapshot.isAuto) } label: {
          Text("Auto")
            .font(.callout.weight(.semibold))
            .foregroundStyle(snapshot.isOn && snapshot.isAuto ? Color.white : Color.primary)
            .frame(width: 62, height: 44)
            .contentShape(.capsule)
        }
        .buttonStyle(PressStyle())
        .controlSurface(active: snapshot.isOn && snapshot.isAuto, shape: .capsule)
        .help(String(localized: "Fan speed follows the air quality"))
        .accessibilityAddTraits(snapshot.isOn && snapshot.isAuto ? .isSelected : [])
      }

      FanSlider(
        speed: snapshot.isOn && !snapshot.isAuto ? snapshot.fanSpeed : nil,
        isRunning: snapshot.isFanRunning,
        isAuto: snapshot.isOn && snapshot.isAuto,
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
    if let dragStep { return String(localized: "Speed \(dragStep)") }
    if isAuto { return String(localized: "Automatic") }
    return speed.map { String(localized: "Speed \($0)") } ?? String(localized: "Off")
  }

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width
      let fill = shown == 0 ? 0 : max(44, width * CGFloat(shown) / 10)

      ZStack(alignment: .leading) {
        Capsule().fill(hovering ? Tokens.track.opacity(1.6) : Tokens.track)

        // Step ticks, so the ten positions are visible before dragging.
        HStack(spacing: 0) {
          ForEach(1..<10) { _ in
            Spacer()
            Capsule().fill(.primary.opacity(0.12)).frame(width: 2, height: 8)
          }
          Spacer()
        }
        .padding(.horizontal, 2)
        .opacity(hovering || dragStep != nil ? 1 : 0)

        Capsule()
          .fill(Color.accentColor.gradient)
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
            onChange(step)
            dragStep = nil
          }
      )
      .onHover { hovering = $0 }
    }
    .frame(height: 44)
    .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: shown)
    .animation(Tokens.hoverMotion, value: hovering)
    .accessibilityElement()
    .accessibilityLabel(String(localized: "Fan speed"))
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
    .padding(.horizontal, 15)
  }

  private func step(at x: CGFloat, width: CGFloat) -> Int {
    min(max(Int(ceil(x / max(width, 1) * 10)), 1), 10)
  }
}

private struct FeatureGrid: View {
  let device: DysonDevice

  var body: some View {
    let snapshot = device.snapshot
    let caps = snapshot.capabilities
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 12) {
      if caps.contains(.heating) {
        RoundToggle(
          title: String(localized: "Heat"),
          detail: snapshot.isHeating
            ? snapshot.heatingTarget.map { $0.formatted(.number.precision(.fractionLength(0))) + "°" } ?? String(localized: "On")
            : String(localized: "Off"),
          symbol: "flame.fill", isActive: snapshot.isHeating, tint: Tokens.heat
        ) { device.setHeating(!snapshot.isHeating) }
      }

      if caps.contains(.humidifier) {
        RoundToggle(
          title: String(localized: "Humidify"),
          detail: snapshot.isHumidifying
            ? (snapshot.isHumidityAuto ? String(localized: "Auto") : snapshot.humidityTarget.map { "\($0) %" } ?? String(localized: "On"))
            : String(localized: "Off"),
          symbol: "drop.fill", isActive: snapshot.isHumidifying, tint: Tokens.water
        ) { device.setHumidifier(!snapshot.isHumidifying) }
      }

      if caps.contains(.oscillation) {
        RoundToggle(
          title: String(localized: "Oscillate"),
          detail: snapshot.isOscillating
            ? snapshot.oscillationWidth.map { "\($0)°" } ?? String(localized: "On") : String(localized: "Off"),
          symbol: "fan.oscillation.fill", isActive: snapshot.isOscillating
        ) { device.setOscillation(!snapshot.isOscillating) }
      }

      if caps.contains(.nightMode) {
        RoundToggle(
          title: String(localized: "Night"),
          detail: snapshot.isNightMode ? String(localized: "Quiet") : String(localized: "Off"),
          symbol: "moon.zzz.fill", isActive: snapshot.isNightMode
        ) { device.setNightMode(!snapshot.isNightMode) }
      }

      if caps.contains(.airflowDirection) {
        RoundToggle(
          title: snapshot.airflowFront ? String(localized: "Cooling") : String(localized: "Diffuse"),
          detail: snapshot.airflowFront ? String(localized: "Front") : String(localized: "Back"),
          symbol: snapshot.airflowFront ? "wind" : "arrow.uturn.backward",
          isActive: snapshot.airflowFront
        ) { device.setAirflow(front: !snapshot.airflowFront) }
      }

      if caps.contains(.sleepTimer) {
        SleepTimerToggle(device: device)
      }
    }
  }
}

private struct RoundToggle: View {
  let title: String
  let detail: String
  let symbol: String
  let isActive: Bool
  var tint: Color = .accentColor
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ToggleFace(title: title, detail: detail, symbol: symbol, isActive: isActive, tint: tint)
    }
    .buttonStyle(PressStyle())
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
  var tint: Color = .accentColor

  @State private var hovering = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 7) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(isActive ? Color.white : Color.primary)
        .contentTransition(.symbolEffect(.replace))
        .symbolEffect(.bounce, value: isActive)
        .frame(width: 52, height: 52)
        .controlSurface(active: isActive, tint: tint, shape: .circle)
        .scaleEffect(hovering ? 1.06 : 1)
      VStack(spacing: 1) {
        Text(title)
          .font(.caption.weight(.semibold))
          .contentTransition(.interpolate)
        Text(detail)
          .font(.caption2.monospacedDigit())
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
    let remaining = device.snapshot.sleepTimer
    Menu {
      Section(String(localized: "Turn off in")) {
        ForEach(DysonDevice.sleepTimerMinutes, id: \.self) { minutes in
          Button(Self.format(minutes)) { device.setSleepTimer(minutes) }
        }
      }
      if remaining != nil {
        Button(String(localized: "Cancel Timer")) { device.setSleepTimer(nil) }
      }
    } label: {
      ToggleFace(
        title: String(localized: "Timer"),
        detail: remaining.map { Self.format($0) } ?? String(localized: "Off"),
        symbol: "timer",
        isActive: remaining != nil
      )
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .frame(maxWidth: .infinity)
    .accessibilityLabel(String(localized: "Sleep timer"))
  }

  static func format(_ minutes: Int) -> String {
    Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
  }
}

private struct HeatingTarget: View {
  let device: DysonDevice
  @State private var pending: Double?

  var body: some View {
    let target = pending ?? device.snapshot.heatingTarget ?? 20
    HStack(spacing: 10) {
      Image(systemName: "thermometer.medium")
        .foregroundStyle(Tokens.heat)
      Text("Heat to")
        .font(.callout)
      Spacer()
      StepButton(symbol: "minus") { change(target - 1) }
        .disabled(target <= 1)
      Text(target.formatted(.number.precision(.fractionLength(0))) + " °C")
        .font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
        .contentTransition(.numericText(value: target))
        .frame(minWidth: 64)
      StepButton(symbol: "plus") { change(target + 1) }
        .disabled(target >= 37)
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
    .background(Tokens.track, in: .capsule)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Heating target"))
    .accessibilityValue(target.formatted(.number.precision(.fractionLength(0))) + " °C")
    .accessibilityAdjustableAction { direction in
      change(direction == .increment ? target + 1 : target - 1)
    }
  }

  /// Rapid clicks only send the last value once they stop.
  private func change(_ value: Double) {
    let value = min(max(value, 1), 37)
    withAnimation(Tokens.hoverMotion) { pending = value }
    Task {
      try? await Task.sleep(for: .milliseconds(450))
      guard pending == value else { return }
      device.setHeatingTarget(value)
      pending = nil
    }
  }
}

private struct StepButton: View {
  let symbol: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .bold))
        .frame(width: 28, height: 28)
        .contentShape(.circle)
    }
    .buttonStyle(PressStyle())
    .controlSurface(active: false, shape: .circle)
  }
}

struct SegmentedChoice<Value: Hashable>: View {
  let options: [Value]
  let selected: Value?
  let label: (Value) -> String
  let accessibilityLabel: String
  let onSelect: (Value) -> Void

  @Namespace private var selection
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.self) { option in
        let isSelected = selected == option
        Button { onSelect(option) } label: {
          Text(label(option))
            .font(.caption.weight(isSelected ? .semibold : .medium).monospacedDigit())
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
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
    .animation(reduceMotion ? nil : Tokens.expandMotion, value: selected)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// A small press-down so every control answers the click before the device does.
struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.94 : 1)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
  }
}
