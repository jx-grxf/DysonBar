import SwiftUI

/// The six bands the MyDyson app and the device display use.
enum AirLevel: Int, Comparable, CaseIterable {
  case good, fair, poor, veryPoor, extremelyPoor, severe

  static func < (lhs: AirLevel, rhs: AirLevel) -> Bool { lhs.rawValue < rhs.rawValue }

  var title: String {
    switch self {
    case .good: "Gut"
    case .fair: "Mäßig"
    case .poor: "Schlecht"
    case .veryPoor: "Sehr schlecht"
    case .extremelyPoor: "Extrem schlecht"
    case .severe: "Gefährlich"
    }
  }

  var color: Color { Tokens.level(self) }

  var symbol: String {
    switch self {
    case .good: "checkmark.circle.fill"
    case .fair: "minus.circle.fill"
    case .poor, .veryPoor: "exclamationmark.triangle.fill"
    case .extremelyPoor, .severe: "xmark.octagon.fill"
    }
  }
}

enum Pollutant: String, CaseIterable, Identifiable {
  case pm25, pm10, voc, no2, hcho

  var id: String { rawValue }

  var title: String {
    switch self {
    case .pm25: "PM2.5"
    case .pm10: "PM10"
    case .voc: "VOC"
    case .no2: "NO₂"
    case .hcho: "HCHO"
    }
  }

  var longTitle: String {
    switch self {
    case .pm25: "Feinstaub PM2.5"
    case .pm10: "Feinstaub PM10"
    case .voc: "Flüchtige organische Verbindungen"
    case .no2: "Stickstoffdioxid"
    case .hcho: "Formaldehyd"
    }
  }

  var unit: String {
    switch self {
    case .pm25, .pm10: "µg/m³"
    case .voc, .no2: "Index"
    case .hcho: "mg/m³"
    }
  }

  /// Upper bound of each band below `.severe`, as shown in the MyDyson app.
  /// VOC and NO₂ stop at "Sehr schlecht" on the device, so their last bands repeat.
  var bands: [Double] {
    switch self {
    case .pm25: [35, 53, 70, 150, 250]
    case .pm10: [50, 75, 100, 350, 420]
    case .voc, .no2: [3, 6, 8, 10, 10]
    case .hcho: [0.099, 0.299, 0.499, 0.999, 0.999]
    }
  }

  func format(_ value: Double) -> String {
    switch self {
    case .pm25, .pm10: value.formatted(.number.precision(.fractionLength(0)))
    case .voc, .no2: value.formatted(.number.precision(.fractionLength(1)))
    case .hcho: value.formatted(.number.precision(.fractionLength(3)))
    }
  }

  func level(for value: Double) -> AirLevel {
    let index = bands.firstIndex { value <= $0 } ?? bands.count
    return AirLevel(rawValue: index) ?? .severe
  }

  /// Continuous position on the 0…6 band scale, so the ring moves smoothly
  /// inside a band instead of jumping between levels.
  func score(for value: Double) -> Double {
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

struct Reading: Identifiable {
  let pollutant: Pollutant
  let value: Double

  var id: Pollutant { pollutant }
  var level: AirLevel { pollutant.level(for: value) }
  var score: Double { pollutant.score(for: value) }
}
