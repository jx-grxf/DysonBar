import DysonKit
import SwiftUI

/// Styled after the purifier's own black display: always dark, colour only for
/// the air quality level, and air streaks that move at the real fan speed.
struct DeviceDisplay: View {
  let device: DysonDevice
  @Binding var chartMetric: Metric?

  private var snapshot: DeviceSnapshot { device.snapshot }
  private var reading: Reading? { snapshot.worstReading }
  private var level: AirLevel { reading?.level ?? .good }
  private var tint: Color { reading == nil ? .white.opacity(0.5) : level.color }

  /// Fraction of the display width a streak travels per second.
  private var flowSpeed: Double {
    guard snapshot.isFanRunning else { return 0 }
    let step = snapshot.isAuto ? 4 : Double(snapshot.fanSpeed ?? 4)
    return 0.05 + step * 0.026
  }

  var body: some View {
    ZStack {
      AirflowField(speed: flowSpeed, sweeping: snapshot.isOscillating && snapshot.isFanRunning, tint: tint)
        .mask(
          LinearGradient(
            colors: [.clear, .white.opacity(0.35), .white],
            startPoint: .leading, endPoint: .trailing))

      HStack(alignment: .center, spacing: 16) {
        LevelRing(score: reading?.score ?? 0, hasValue: reading != nil, level: level) {
          VStack(spacing: 2) {
            Text(reading?.level.title ?? "–")
              .font(.system(size: titleSize, weight: .semibold, design: .rounded))
              .foregroundStyle(tint)
              .multilineTextAlignment(.center)
              .lineLimit(2)
              .minimumScaleFactor(0.7)
              .contentTransition(.interpolate)
            if let reading {
              Text("\(reading.pollutant.title) \(reading.pollutant.format(reading.value))")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .contentTransition(.numericText(value: reading.value))
            } else {
              Text("Waiting for data")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            }
          }
          .padding(.horizontal, 22)
        }
        .frame(width: 138, height: 138)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Air quality"))
        .accessibilityValue(airAccessibilityValue)

        VStack(alignment: .trailing, spacing: 10) {
          Spacer(minLength: 0)
          climate
          if snapshot.capabilities.contains(.heating), snapshot.isOn, snapshot.isHeating,
            let target = snapshot.heatingTarget
          {
            TargetBadge(symbol: "flame.fill", text: target.formatted(.number.precision(.fractionLength(0))) + "°", tint: Tokens.heat)
          }
          if snapshot.capabilities.contains(.humidifier), snapshot.isOn, snapshot.isHumidifying {
            TargetBadge(
              symbol: "drop.fill",
              text: snapshot.isHumidityAuto ? String(localized: "Auto") : snapshot.humidityTarget.map { "\($0) %" } ?? "–",
              tint: Tokens.water)
          }
          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 16)
    }
    .frame(height: 170)
    .background(Tokens.display, in: .rect(cornerRadius: Tokens.displayRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Tokens.displayRadius, style: .continuous)
        .strokeBorder(.white.opacity(0.08))
    }
    .clipShape(.rect(cornerRadius: Tokens.displayRadius, style: .continuous))
    .environment(\.colorScheme, .dark)
    .animation(Tokens.dataMotion, value: level)
  }

  private var titleSize: CGFloat {
    (reading?.level.title.count ?? 0) > 9 ? 17 : 22
  }

  private var climate: some View {
    VStack(alignment: .trailing, spacing: 4) {
      Button { toggle(.temperature) } label: {
        Text(snapshot.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" } ?? "–")
          .font(.system(size: 34, weight: .medium, design: .rounded).monospacedDigit())
          .foregroundStyle(.white)
          .contentTransition(.numericText(value: snapshot.temperature ?? 0))
      }
      .buttonStyle(DisplayButtonStyle(isSelected: chartMetric == .temperature))
      .help(String(localized: "Temperature history"))
      .accessibilityLabel(String(localized: "Temperature"))
      .accessibilityValue(snapshot.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + " °C" } ?? "–")

      Button { toggle(.humidity) } label: {
        Label(snapshot.humidity.map { "\($0) %" } ?? "–", systemImage: "humidity.fill")
          .font(.callout.weight(.medium).monospacedDigit())
          .foregroundStyle(.white.opacity(0.6))
          .contentTransition(.numericText(value: Double(snapshot.humidity ?? 0)))
      }
      .buttonStyle(DisplayButtonStyle(isSelected: chartMetric == .humidity))
      .help(String(localized: "Humidity history"))
      .accessibilityLabel(String(localized: "Humidity"))
      .accessibilityValue(snapshot.humidity.map { "\($0) %" } ?? "–")
    }
  }

  private func toggle(_ metric: Metric) {
    chartMetric = chartMetric == metric ? nil : metric
  }

  private var airAccessibilityValue: String {
    guard let reading else { return String(localized: "Waiting for data") }
    return "\(reading.level.title), \(reading.pollutant.longTitle) \(reading.pollutant.format(reading.value)) \(reading.pollutant.unit)"
  }
}

private struct TargetBadge: View {
  let symbol: String
  let text: String
  let tint: Color

  var body: some View {
    Label(text, systemImage: symbol)
      .font(.caption.weight(.semibold).monospacedDigit())
      .foregroundStyle(tint)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(tint.opacity(0.16), in: .capsule)
  }
}

private struct DisplayButtonStyle: ButtonStyle {
  let isSelected: Bool
  @State private var hovering = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(
        .white.opacity(isSelected ? 0.14 : hovering ? 0.07 : 0),
        in: .rect(cornerRadius: 8, style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .onHover { hovering = $0 }
      .animation(Tokens.hoverMotion, value: hovering)
      .animation(Tokens.hoverMotion, value: isSelected)
  }
}

/// The device's ring: six bands around 270°, lit up to the current score.
/// `Animatable`, so the light runs along the ring when a new value arrives.
private struct LevelRing<Content: View>: View, Animatable {
  var score: Double
  let hasValue: Bool
  let level: AirLevel
  @ViewBuilder let content: Content

  var animatableData: Double {
    get { score }
    set { score = newValue }
  }

  private static var sweep: Double { 270 }
  private static var start: Double { 135 }
  private static var gap: Double { 3.5 }

  var body: some View {
    ZStack {
      Canvas { context, size in
        let count = AirLevel.allCases.count
        let lineWidth: CGFloat = 9
        let radius = min(size.width, size.height) / 2 - lineWidth / 2
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let band = Self.sweep / Double(count)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        for step in AirLevel.allCases {
          let from = Self.start + Double(step.rawValue) * band + Self.gap / 2
          let to = from + band - Self.gap
          var track = Path()
          track.addArc(center: centre, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
          // A neutral track: dimmed band colours turn muddy on the black display.
          context.stroke(track, with: .color(.white.opacity(0.09)), style: style)

          guard hasValue else { continue }
          let fill = min(max(score - Double(step.rawValue), 0), 1)
          guard fill > 0 else { continue }
          var lit = Path()
          lit.addArc(
            center: centre, radius: radius, startAngle: .degrees(from),
            endAngle: .degrees(from + (to - from) * fill), clockwise: false)
          context.stroke(lit, with: .color(step.color), style: style)
        }

        guard hasValue else { return }
        let clamped = min(max(score, 0), Double(count))
        let index = min(Int(clamped), count - 1)
        let within = clamped - Double(index)
        let angle = Self.start + Double(index) * band + Self.gap / 2 + (band - Self.gap) * within
        let point = CGPoint(
          x: centre.x + radius * cos(angle * .pi / 180),
          y: centre.y + radius * sin(angle * .pi / 180))
        let knob = CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13)
        context.fill(Path(ellipseIn: knob.insetBy(dx: -2, dy: -2)), with: .color(Tokens.display))
        context.fill(Path(ellipseIn: knob), with: .color(.white))
      }
      content
    }
  }
}

private struct AirflowField: View {
  let speed: Double
  let sweeping: Bool
  let tint: Color

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private struct Streak {
    let y: Double
    let phase: Double
    let length: Double
    let pace: Double
    let alpha: Double
  }

  /// Fixed seeds so the field looks the same every time the panel opens.
  private static let streaks: [Streak] = {
    var generator = SplitMix(seed: 0xD7_50_4E)
    return (0..<42).map { _ in
      Streak(
        y: generator.next(in: 0.05...0.95),
        phase: generator.next(in: 0...1),
        length: generator.next(in: 26...92),
        pace: generator.next(in: 0.6...1.4),
        alpha: generator.next(in: 0.14...0.45)
      )
    }
  }()

  var body: some View {
    let isMoving = speed > 0 && !reduceMotion
    TimelineView(.animation(paused: !isMoving)) { context in
      let time = isMoving ? context.date.timeIntervalSinceReferenceDate : 0
      Canvas { canvas, size in
        for streak in Self.streaks {
          let travel = (streak.phase + time * speed * streak.pace).truncatingRemainder(dividingBy: 1)
          let x = travel * (size.width + streak.length) - streak.length
          let wave = sweeping ? sin(time * 0.7 + streak.phase * 6) * 7 : 0
          let y = streak.y * size.height + wave
          var path = Path()
          path.move(to: CGPoint(x: x, y: y))
          path.addLine(to: CGPoint(x: x + streak.length, y: y))
          let alpha = speed > 0 ? streak.alpha : streak.alpha * 0.3
          canvas.stroke(
            path,
            with: .linearGradient(
              Gradient(colors: [tint.opacity(0), tint.opacity(alpha)]),
              startPoint: CGPoint(x: x, y: y),
              endPoint: CGPoint(x: x + streak.length, y: y)
            ),
            style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
          )
        }
      }
    }
    .allowsHitTesting(false)
  }
}

private struct SplitMix {
  var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next(in range: ClosedRange<Double>) -> Double {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    z ^= z >> 31
    let unit = Double(z >> 11) / Double(1 << 53)
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
  }
}
