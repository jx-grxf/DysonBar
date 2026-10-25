import Foundation

/// Everything the device has told us, as raw key/value strings, plus typed
/// accessors. Kept free of networking so the parsing can be tested on its own.
public struct DeviceSnapshot: Equatable, Sendable {
  public var state: [String: String] = [:]
  public var sensors: [String: String] = [:]
  /// Fault codes whose value is anything but "OK", e.g. `["fltr": "FAIL"]`.
  public var faults: [String: String] = [:]
  public var lastUpdate: Date?

  public init() {}

  public enum Change {
    case state, sensors, faults, none
  }

  /// Applies one MQTT payload and says what changed.
  @discardableResult
  public mutating func apply(_ payload: Data, now: Date = .now) -> Change {
    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return .none }
    switch json["msg"] as? String {
    case "CURRENT-STATE", "STATE-CHANGE":
      // STATE-CHANGE sends [old, new] pairs, CURRENT-STATE plain strings.
      for (key, value) in json["product-state"] as? [String: Any] ?? [:] {
        if let pair = value as? [String], let latest = pair.last {
          state[key] = latest
        } else if let string = value as? String {
          state[key] = string
        }
      }
      lastUpdate = now
      return .state
    case "ENVIRONMENTAL-CURRENT-SENSOR-DATA":
      for (key, value) in json["data"] as? [String: Any] ?? [:] {
        if let string = value as? String { sensors[key] = string }
      }
      lastUpdate = now
      return .sensors
    case "CURRENT-FAULTS", "FAULTS-CHANGE":
      // A full report replaces the list, a change only touches the codes it names.
      if json["msg"] as? String == "CURRENT-FAULTS" { faults = [:] }
      for group in ["product-errors", "product-warnings", "module-errors", "module-warnings"] {
        for (code, value) in json[group] as? [String: Any] ?? [:] {
          guard let latest = (value as? [String])?.last ?? (value as? String) else { continue }
          faults[code] = latest == "OK" ? nil : latest
        }
      }
      return .faults
    default:
      return .none
    }
  }

  // MARK: Typed state

  public var isOn: Bool { state["fpwr"] == "ON" }
  public var isAuto: Bool { state["auto"] == "ON" }
  public var isNightMode: Bool { state["nmod"] == "ON" }
  public var isOscillating: Bool { ["ON", "OION"].contains(state["oson"]) }
  public var airflowFront: Bool { (state["fdir"] ?? "ON") == "ON" }
  public var fanSpeed: Int? { state["fnsp"].flatMap(Int.init) }
  public var isFanRunning: Bool { isOn && state["fnst"] == "FAN" }
  public var hasData: Bool { !state.isEmpty }

  public var oscillationWidth: Int? {
    guard let low = state["osal"].flatMap(Int.init), let high = state["osau"].flatMap(Int.init) else {
      return nil
    }
    return high - low
  }

  /// Remaining minutes; the device counts down and reports "OFF" when idle.
  public var sleepTimer: Int? { state["sltm"].flatMap(Int.init) }

  /// Percent left. "INV" means the model has no separate filter of that kind.
  public var hepaFilter: Int? { state["hflr"].flatMap(Int.init) }
  public var carbonFilter: Int? { state["cflr"].flatMap(Int.init) }

  public var isHeating: Bool { state["hmod"] == "HEAT" }
  /// Heating target in °C; the device stores tenths of a kelvin.
  public var heatingTarget: Double? {
    state["hmax"].flatMap(Double.init).map { ($0 / 10 - 273.15).rounded() }
  }

  public var isHumidifying: Bool { state["hume"] == "HUMD" }
  public var isHumidityAuto: Bool { state["haut"] == "ON" }
  public var humidityTarget: Int? { state["humt"].flatMap(Int.init) }

  /// The device's own warning code; "NONE" when all is well.
  public var warningCode: String? {
    guard let code = state["wacd"], code != "NONE" else { return nil }
    return code
  }

  public var temperature: Double? {
    sensors["tact"].flatMap(Double.init).map { $0 / 10 - 273.15 }
  }

  public var humidity: Int? { sensors["hact"].flatMap(Int.init) }

  public var readings: [Reading] {
    Pollutant.allCases.compactMap { pollutant in
      value(for: pollutant).map { Reading(pollutant: pollutant, value: $0) }
    }
  }

  /// The pollutant furthest up its scale decides the overall rating, like on the device.
  public var worstReading: Reading? { readings.max { $0.score < $1.score } }

  public func value(for pollutant: Pollutant) -> Double? {
    func number(_ keys: String...) -> Double? {
      keys.lazy.compactMap { self.sensors[$0].flatMap(Double.init) }.first
    }
    switch pollutant {
    case .pm25: return number("p25r", "pm25")
    case .pm10: return number("p10r", "pm10")
    case .voc: return number("va10").map { $0 / 10 }
    case .no2: return number("noxl").map { $0 / 10 }
    case .hcho: return number("hchr").map { $0 / 1000 }
    }
  }

  public var capabilities: Capabilities { Capabilities(state: state) }
}

/// What a model can do, read from the keys it reports instead of a model table,
/// so devices we never tested still get the right controls.
public struct Capabilities: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let auto = Capabilities(rawValue: 1 << 0)
  public static let oscillation = Capabilities(rawValue: 1 << 1)
  public static let oscillationAngles = Capabilities(rawValue: 1 << 2)
  public static let airflowDirection = Capabilities(rawValue: 1 << 3)
  public static let nightMode = Capabilities(rawValue: 1 << 4)
  public static let sleepTimer = Capabilities(rawValue: 1 << 5)
  public static let heating = Capabilities(rawValue: 1 << 6)
  public static let humidifier = Capabilities(rawValue: 1 << 7)

  init(state: [String: String]) {
    var set: Capabilities = []
    if state["auto"] != nil { set.insert(.auto) }
    if state["oson"] != nil { set.insert(.oscillation) }
    if state["osal"] != nil, state["osau"] != nil { set.insert(.oscillationAngles) }
    if state["fdir"] != nil { set.insert(.airflowDirection) }
    if state["nmod"] != nil { set.insert(.nightMode) }
    if state["sltm"] != nil { set.insert(.sleepTimer) }
    if state["hmod"] != nil { set.insert(.heating) }
    if state["hume"] != nil { set.insert(.humidifier) }
    self = set
  }
}

public enum DeviceCommand {
  public static func power(_ on: Bool) -> [String: String] { ["fpwr": on ? "ON" : "OFF"] }

  public static func auto(_ on: Bool) -> [String: String] { ["auto": on ? "ON" : "OFF", "fpwr": "ON"] }

  public static func speed(_ speed: Int) -> [String: String] {
    ["fpwr": "ON", "auto": "OFF", "fnsp": String(format: "%04d", min(max(speed, 1), 10))]
  }

  public static func nightMode(_ on: Bool) -> [String: String] { ["nmod": on ? "ON" : "OFF"] }

  public static func airflow(front: Bool) -> [String: String] { ["fdir": front ? "ON" : "OFF"] }

  public static func sleepTimer(_ minutes: Int?) -> [String: String] {
    ["sltm": minutes.map { String(format: "%04d", $0) } ?? "OFF"]
  }

  /// Keeps the current centre of the sweep and widens or narrows it around it.
  /// The device accepts angles from 5° to 355°.
  public static func oscillation(width: Int, current state: [String: String]) -> [String: String] {
    let low = state["osal"].flatMap(Int.init) ?? 135
    let high = state["osau"].flatMap(Int.init) ?? 225
    let centre = (low + high) / 2
    var newLow = max(5, centre - width / 2)
    var newHigh = newLow + width
    if newHigh > 355 {
      newHigh = 355
      newLow = newHigh - width
    }
    return [
      "oson": "ON", "fpwr": "ON", "ancp": "CUST",
      "osal": String(format: "%04d", newLow), "osau": String(format: "%04d", newHigh),
    ]
  }

  public static func heating(_ on: Bool) -> [String: String] { ["hmod": on ? "HEAT" : "OFF"] }

  public static func heatingTarget(celsius: Double) -> [String: String] {
    let clamped = min(max(celsius, 1), 37)
    return ["hmod": "HEAT", "hmax": String(format: "%04d", Int(((clamped + 273.15) * 10).rounded()))]
  }

  public static func humidifier(_ on: Bool) -> [String: String] { ["hume": on ? "HUMD" : "OFF"] }

  public static func humidityAuto(_ on: Bool) -> [String: String] {
    ["hume": "HUMD", "haut": on ? "ON" : "OFF"]
  }

  public static func humidityTarget(_ percent: Int) -> [String: String] {
    ["hume": "HUMD", "haut": "OFF", "humt": String(format: "%04d", min(max(percent, 30), 70))]
  }
}
