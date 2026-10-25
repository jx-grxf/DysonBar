import SwiftUI

enum Tokens {
  /// 360 pt: five sensor columns still fit, and the popover stays as compact as Control Center.
  static let panelWidth: CGFloat = 360
  static let padding: CGFloat = 16

  static let cardFill = Color.primary.opacity(0.045)
  static let track = Color.primary.opacity(0.09)
  static let hover = Color.primary.opacity(0.06)

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

  static let hoverMotion = Animation.snappy(duration: 0.16)
  static let expandMotion = Animation.snappy(duration: 0.22)
  /// Sensor values arrive every ~30 s; a slower ease makes the ring settle instead of snap.
  static let dataMotion = Animation.smooth(duration: 0.6)
}

extension View {
  /// Liquid Glass on macOS 26 and later, a plain fill before that and with
  /// "Reduce transparency".
  @ViewBuilder
  func controlSurface(active: Bool, shape: some Shape = .rect(cornerRadius: 12, style: .continuous))
    -> some View
  {
    modifier(ControlSurface(active: active, shape: AnyShape(shape)))
  }
}

private struct ControlSurface: ViewModifier {
  let active: Bool
  let shape: AnyShape
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  func body(content: Content) -> some View {
    if #available(macOS 26, *), !reduceTransparency {
      content.glassEffect(
        active ? .regular.tint(Color.accentColor.opacity(0.85)).interactive() : .regular.interactive(),
        in: shape
      )
    } else {
      content.background(active ? Color.accentColor : Tokens.hover, in: shape)
    }
  }
}
