import Foundation

/// The six bands the MyDyson app and the device display use.
public enum AirLevel: Int, Comparable, CaseIterable, Codable, Sendable {
  case good, fair, poor, veryPoor, extremelyPoor, severe

  public static func < (lhs: AirLevel, rhs: AirLevel) -> Bool { lhs.rawValue < rhs.rawValue }

  public var title: String {
    switch self {
    case .good: String(localized: "Good")
    case .fair: String(localized: "Fair")
    case .poor: String(localized: "Poor")
    case .veryPoor: String(localized: "Very poor")
    case .extremelyPoor: String(localized: "Extremely poor")
    case .severe: String(localized: "Severe")
    }
  }

  public var symbol: String {
    switch self {
    case .good: "checkmark.circle.fill"
    case .fair: "minus.circle.fill"
    case .poor, .veryPoor: "exclamationmark.triangle.fill"
    case .extremelyPoor, .severe: "xmark.octagon.fill"
    }
  }
}

public enum Pollutant: String, CaseIterable, Identifiable, Codable, Sendable {
  case pm25, pm10, voc, no2, hcho

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .pm25: "PM2.5"
    case .pm10: "PM10"
    case .voc: "VOC"
    case .no2: "NO₂"
    case .hcho: "HCHO"
    }
  }

  public var longTitle: String {
    switch self {
    case .pm25: String(localized: "Fine particles PM2.5")
    case .pm10: String(localized: "Particles PM10")
    case .voc: String(localized: "Volatile organic compounds")
    case .no2: String(localized: "Nitrogen dioxide")
    case .hcho: String(localized: "Formaldehyde")
    }
  }

  public var unit: String {
    switch self {
    case .pm25, .pm10: "µg/m³"
    case .voc, .no2: String(localized: "index")
    case .hcho: "mg/m³"
    }
  }

  /// Upper bound of each band below `.severe`, as shown in the MyDyson app.
  /// VOC and NO₂ stop at "very poor" on the device, so their last bands repeat.
  public var bands: [Double] {
    switch self {
    case .pm25: [35, 53, 70, 150, 250]
    case .pm10: [50, 75, 100, 350, 420]
    case .voc, .no2: [3, 6, 8, 10, 10]
    case .hcho: [0.099, 0.299, 0.499, 0.999, 0.999]
    }
  }

  public func format(_ value: Double) -> String {
    switch self {
    case .pm25, .pm10: value.formatted(.number.precision(.fractionLength(0)))
    case .voc, .no2: value.formatted(.number.precision(.fractionLength(1)))
    case .hcho: value.formatted(.number.precision(.fractionLength(3)))
    }
  }

  public func level(for value: Double) -> AirLevel {
    let index = bands.firstIndex { value <= $0 } ?? bands.count
    return AirLevel(rawValue: index) ?? .severe
  }

  /// Continuous position on the 0…6 band scale, so gauges move smoothly
  /// inside a band instead of jumping between levels.
  public func score(for value: Double) -> Double {
    var lower = 0.0
    for (index, upper) in bands.enumerated() {
      if value <= upper {
        let span = max(upper - lower, .ulpOfOne)
        return Double(index) + (value - lower) / span
      }
      lower = upper
    }
    return Double(bands.count)
  }
}

public struct Reading: Identifiable, Equatable, Sendable {
  public let pollutant: Pollutant
  public let value: Double

  public init(pollutant: Pollutant, value: Double) {
    self.pollutant = pollutant
    self.value = value
  }

  public var id: Pollutant { pollutant }
  public var level: AirLevel { pollutant.level(for: value) }
  public var score: Double { pollutant.score(for: value) }
}
