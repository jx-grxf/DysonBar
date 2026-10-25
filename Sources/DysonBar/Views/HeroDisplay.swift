import SwiftUI

/// Styled after the purifier's own black display: always dark, colour only for
/// the air quality level, and air streaks that move at the real fan speed.
struct HeroDisplay: View {
  let device: DysonDevice

  private var reading: Reading? { device.worstReading }
  private var level: AirLevel { reading?.level ?? .good }
  private var tint: Color { reading == nil ? .white.opacity(0.5) : level.color }

  /// Fraction of the panel width a streak travels per second.
  private var flowSpeed: Double {
    guard device.isFanRunning else { return 0 }
    let step = device.isAuto ? 4 : Double(device.fanSpeed ?? 4)
    return 0.06 + step * 0.028
  }

  var body: some View {
    ZStack {
      AirflowField(speed: flowSpeed, sweeping: device.isOscillating && device.isFanRunning, tint: tint)
        .mask(LinearGradient(colors: [.white.opacity(0.15), .white.opacity(0.7), .white], startPoint: .leading, endPoint: .trailing))

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Luftqualität")
              .font(.caption2.weight(.semibold))
              .textCase(.uppercase)
              .tracking(0.8)
              .foregroundStyle(.white.opacity(0.45))
            Text(reading?.level.title ?? "–")
              .font(.system(size: 36, weight: .semibold, design: .rounded))
              .foregroundStyle(tint)
              .contentTransition(.interpolate)
            Text(detail)
              .font(.caption.monospacedDigit())
              .foregroundStyle(.white.opacity(0.55))
              .contentTransition(.numericText())
          }

          Spacer(minLength: 12)

          VStack(alignment: .trailing, spacing: 3) {
            Text(device.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + "°" } ?? "–")
              .font(.system(size: 26, weight: .medium, design: .rounded).monospacedDigit())
              .foregroundStyle(.white)
              .contentTransition(.numericText())
            Label(device.humidity.map { "\($0) %" } ?? "–", systemImage: "humidity.fill")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.white.opacity(0.55))
          }
        }

        Spacer(minLength: 16)

        LevelScale(score: reading?.score, level: level)
      }
      .padding(18)
    }
    .frame(height: 176)
    .background(Color(white: 0.055), in: .rect(cornerRadius: 20, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(.white.opacity(0.08))
    }
    .clipShape(.rect(cornerRadius: 20, style: .continuous))
    .environment(\.colorScheme, .dark)
    .animation(Tokens.dataMotion, value: level)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Luftqualität \(reading?.level.title ?? "unbekannt")")
    .accessibilityValue(accessibilityText)
  }

  private var detail: String {
    guard let reading else { return "Warte auf Messwerte" }
    return "Bestimmt durch \(reading.pollutant.title) · \(reading.pollutant.format(reading.value)) \(reading.pollutant.unit)"
  }

  private var accessibilityText: String {
    var parts = [detail]
    if let temperature = device.temperature {
      parts.append("\(temperature.formatted(.number.precision(.fractionLength(1)))) Grad")
    }
    if let humidity = device.humidity { parts.append("\(humidity) Prozent Luftfeuchte") }
    return parts.joined(separator: ", ")
  }
}

private struct LevelScale: View {
  let score: Double?
  let level: AirLevel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: 7) {
      GeometryReader { proxy in
        let count = AirLevel.allCases.count
        ZStack(alignment: .leading) {
          HStack(spacing: 3) {
            ForEach(AirLevel.allCases, id: \.self) { step in
              Capsule()
                .fill(step.color.opacity(step == level ? 1 : 0.22))
            }
          }
          if let score {
            let position = min(max(score / Double(count), 0), 1) * proxy.size.width
            Circle()
              .fill(.white)
              .frame(width: 10, height: 10)
              .shadow(color: .black.opacity(0.5), radius: 3)
              .offset(x: min(max(position - 5, 0), proxy.size.width - 10))
          }
        }
      }
      .frame(height: 10)

      HStack {
        Text("Gut")
        Spacer()
        Text("Gefährlich")
      }
      .font(.caption2)
      .foregroundStyle(.white.opacity(0.35))
    }
    .animation(reduceMotion ? nil : Tokens.dataMotion, value: score)
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
    return (0..<38).map { _ in
      Streak(
        y: generator.next(in: 0.06...0.94),
        phase: generator.next(in: 0...1),
        length: generator.next(in: 28...96),
        pace: generator.next(in: 0.6...1.4),
        alpha: generator.next(in: 0.16...0.5)
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
          let alpha = speed > 0 ? streak.alpha : streak.alpha * 0.35
          canvas.stroke(
            path,
            with: .linearGradient(
              Gradient(colors: [tint.opacity(0), tint.opacity(alpha)]),
              startPoint: CGPoint(x: x, y: y),
              endPoint: CGPoint(x: x + streak.length, y: y)
            ),
            style: StrokeStyle(lineWidth: 1.4, lineCap: .round)
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
