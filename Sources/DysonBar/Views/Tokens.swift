import DysonKit
import SwiftUI

enum Tokens {
  /// 400 pt: five sensor columns with sparklines fit without truncating, and the
  /// panel stays inside the 400–440 pt range of the other menu bar apps.
  static let panelWidth: CGFloat = 400
  static let padding: CGFloat = 16
  static let displayRadius: CGFloat = 22
  static let cardRadius: CGFloat = 14

  static let cardFill = Color.primary.opacity(0.045)
  static let track = Color.primary.opacity(0.09)
  static let hover = Color.primary.opacity(0.06)
  /// The purifier's own display is near-black glass, not pure black.
  static let display = Color(white: 0.055)

  /// Same order and hues as the MyDyson app and the device ring,
  /// so the colours read the same in all three places.
  static func level(_ level: AirLevel) -> Color {
    switch level {
    case .good: Color(red: 0.24, green: 0.78, blue: 0.47)
    case .fair: Color(red: 0.98, green: 0.80, blue: 0.20)
    case .poor: Color(red: 0.98, green: 0.55, blue: 0.18)
    case .veryPoor: Color(red: 0.92, green: 0.26, blue: 0.24)
    case .extremelyPoor: Color(red: 0.62, green: 0.30, blue: 0.85)
    case .severe: Color(red: 0.55, green: 0.10, blue: 0.22)
    }
  }

  static let heat = Color(red: 1.0, green: 0.48, blue: 0.22)
  static let water = Color(red: 0.25, green: 0.62, blue: 1.0)

  static let hoverMotion = Animation.snappy(duration: 0.16)
  static let expandMotion = Animation.snappy(duration: 0.24)
  static let switchMotion = Animation.smooth(duration: 0.28)
  /// Sensor values arrive every ~30 s; a slower ease makes gauges settle instead of snap.
  static let dataMotion = Animation.smooth(duration: 0.8)
}

extension AirLevel {
  var color: Color { Tokens.level(self) }
}

extension View {
  /// Liquid Glass on macOS 26 and later, a plain fill before that and with
  /// "Reduce transparency".
  func controlSurface(active: Bool, tint: Color = .accentColor, shape: some Shape = .rect(cornerRadius: 12, style: .continuous))
    -> some View
  {
    modifier(ControlSurface(active: active, tint: tint, shape: AnyShape(shape)))
  }
}

extension EnvironmentValues {
  /// `ImageRenderer` can't draw Liquid Glass, so snapshots use the plain fallback.
  @Entry var isSnapshot = false
  /// Drives the ring sweep frame by frame, since `ImageRenderer` doesn't animate.
  @Entry var snapshotProgress = 1.0
}

private struct ControlSurface: ViewModifier {
  let active: Bool
  let tint: Color
  let shape: AnyShape
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.isSnapshot) private var isSnapshot

  func body(content: Content) -> some View {
    if #available(macOS 26, *), !reduceTransparency, !isSnapshot {
      content.glassEffect(
        active ? .regular.tint(tint.opacity(0.85)).interactive() : .regular.interactive(),
        in: shape
      )
    } else {
      content.background(active ? tint : Tokens.hover, in: shape)
    }
  }
}
