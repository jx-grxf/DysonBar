import AppKit
import Foundation
import Network
import Observation
import os

@MainActor
@Observable
final class DysonDevice {
  enum Connection: Equatable {
    case searching
    case connecting(String)
    case connected(String)
    case offline(String)
    case setupMissing(String)

    var isConnected: Bool {
      if case .connected = self { return true }
      return false
    }
  }

  enum Airflow: String { case front = "ON", back = "OFF" }

  static let oscillationWidths = [45, 90, 180, 350]
  static let sleepTimerMinutes = [15, 30, 60, 120, 240, 480]

  private(set) var connection: Connection = .searching
  private(set) var config: DeviceConfig?
  private(set) var state: [String: String] = [:]
  private(set) var sensors: [String: String] = [:]
  private(set) var lastUpdate: Date?

  private var password = ""
  private var client: MQTTClient?
  private var browser: NWBrowser?
  private var retryDelay: Duration = .seconds(2)
  private var retryTask: Task<Void, Never>?
  private var pollTask: Task<Void, Never>?
  private var pendingRoutes: [Route] = []
  private let log = Logger(subsystem: "at.johannesgrof.DysonBar", category: "connection")

  init() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reconnect() }
    }
  }

  var name: String { config?.name ?? "Dyson" }
  var isOn: Bool { state["fpwr"] == "ON" }
  var isAuto: Bool { state["auto"] == "ON" }
  var isNightMode: Bool { state["nmod"] == "ON" }
  var isOscillating: Bool { ["ON", "OION"].contains(state["oson"]) }
  var airflow: Airflow { Airflow(rawValue: state["fdir"] ?? "ON") ?? .front }
  var fanSpeed: Int? { state["fnsp"].flatMap(Int.init) }
  var isFanRunning: Bool { isOn && state["fnst"] == "FAN" }
  var hasData: Bool { !state.isEmpty }

  var oscillationWidth: Int? {
    guard let low = state["osal"].flatMap(Int.init), let high = state["osau"].flatMap(Int.init) else {
      return nil
    }
    return high - low
  }

  /// Remaining minutes; the device counts down and reports "OFF" when idle.
  var sleepTimer: Int? { state["sltm"].flatMap(Int.init) }

  var filterLife: Int? { state["hflr"].flatMap(Int.init) }

  var temperature: Double? {
    sensors["tact"].flatMap(Double.init).map { $0 / 10 - 273.15 }
  }

  var humidity: Int? { sensors["hact"].flatMap(Int.init) }

  var readings: [Reading] {
    Pollutant.allCases.compactMap { pollutant in
      value(for: pollutant).map { Reading(pollutant: pollutant, value: $0) }
    }
  }

  /// The pollutant furthest up its scale decides the overall rating, like on the device.
  var worstReading: Reading? { readings.max { $0.score < $1.score } }

  private func value(for pollutant: Pollutant) -> Double? {
    func number(_ keys: String...) -> Double? {
      keys.lazy.compactMap { self.sensors[$0].flatMap(Double.init) }.first
    }
    switch pollutant {
    case .pm25: return number("p25r", "pm25")
    case .pm10: return number("p10r", "pm10")
    case .voc: return number("va10").map { $0 / 10 }
    case .no2: return number("noxl").map { $0 / 10 }
    case .hcho: return number("hchr", "hcho").map { $0 / 1000 }
    }
  }

  func start() {
    do {
      let (config, password) = try DeviceConfig.loadFirst()
      self.config = config
      self.password = password
      connect()
    } catch {
      connection = .setupMissing(error.localizedDescription)
    }
  }

  func reconnect() {
    guard config != nil else { return start() }
    retryDelay = .seconds(2)
    connect()
  }

  private enum Route {
    case host(String)
    case bonjour
  }

  private static let lastHostKey = "lastHost"

  /// Cheapest first: the address that worked last time, then Bonjour, then the
  /// serial as a hostname, which most home routers resolve from DHCP.
  private func routes(for config: DeviceConfig) -> [Route] {
    if let host = config.host { return [.host(host)] }
    var routes: [Route] = []
    if let last = UserDefaults.standard.string(forKey: Self.lastHostKey) {
      routes.append(.host(last))
    }
    routes.append(.bonjour)
    routes.append(.host(config.serial.lowercased()))
    return routes
  }

  private func connect() {
    guard let config else { return }
    teardown()
    pendingRoutes = routes(for: config)
    tryNextRoute(lastError: nil)
  }

  private func tryNextRoute(lastError: String?) {
    guard !pendingRoutes.isEmpty else {
      log.info("all routes failed: \(lastError ?? "-", privacy: .public)")
      connection = .offline(lastError ?? "Keine Antwort")
      scheduleRetry()
      return
    }
    switch pendingRoutes.removeFirst() {
    case .host(let host):
      open(.hostPort(host: .init(host), port: 1883), label: host)
    case .bonjour:
      browse()
    }
  }

  private func browse() {
    guard let config else { return }
    connection = .searching
    log.info("browsing for \(config.serial, privacy: .public)")
    let browser = NWBrowser(for: .bonjour(type: "_dyson_mqtt._tcp", domain: "local."), using: .tcp)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let match = results.first {
        if case .service(let name, _, _, _) = $0.endpoint { return name.hasSuffix(config.serial) }
        return false
      }
      guard let match else { return }
      Task { @MainActor in self?.found(match.endpoint) }
    }
    browser.start(queue: .main)
    self.browser = browser

    retryTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(4))
      guard let self, !Task.isCancelled, self.browser != nil else { return }
      self.browser?.cancel()
      self.browser = nil
      self.tryNextRoute(lastError: "Nicht per Bonjour gefunden")
    }
  }

  private func found(_ endpoint: NWEndpoint) {
    guard browser != nil, client == nil else { return }
    browser?.cancel()
    browser = nil
    retryTask?.cancel()
    open(endpoint, label: "Bonjour")
  }

  private func open(_ endpoint: NWEndpoint, label: String) {
    guard let config else { return }
    log.info("connecting via \(label, privacy: .public)")
    connection = .connecting(label)
    let client = MQTTClient(endpoint: endpoint, username: config.serial, password: password)
    let root = "\(config.topicRoot)/\(config.serial)"
    client.onEvent = { [weak self, weak client] event in
      Task { @MainActor in
        guard let self, let client, client === self.client else { return }
        self.handle(event, label: label)
      }
    }
    self.client = client
    client.start(subscribing: ["\(root)/status/current", "\(root)/status/faults"])
  }

  private func teardown() {
    retryTask?.cancel()
    pollTask?.cancel()
    browser?.cancel()
    browser = nil
    client?.stop()
    client = nil
  }

  private func handle(_ event: MQTTClient.Event, label: String) {
    switch event {
    case .connected(let remoteHost):
      log.info("connected via \(label, privacy: .public) to \(remoteHost ?? "?", privacy: .public)")
      if let remoteHost { UserDefaults.standard.set(remoteHost, forKey: Self.lastHostKey) }
      connection = .connected(remoteHost ?? label)
      pendingRoutes = []
      retryDelay = .seconds(2)
      requestEverything()
      pollTask = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(30))
          self?.request("REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA")
        }
      }
    case .message(_, let payload):
      apply(payload)
    case .disconnected(let reason):
      log.info("disconnected (\(label, privacy: .public)): \(reason, privacy: .public)")
      let wasConnected = connection.isConnected
      client = nil
      pollTask?.cancel()
      if wasConnected {
        connection = .offline(reason)
        scheduleRetry()
      } else {
        tryNextRoute(lastError: reason)
      }
    }
  }

  private func scheduleRetry() {
    retryTask?.cancel()
    let delay = retryDelay
    retryDelay = min(retryDelay * 2, .seconds(30))
    retryTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.connect()
    }
  }

  private func apply(_ payload: Data) {
    guard let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
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
      lastUpdate = .now
    case "ENVIRONMENTAL-CURRENT-SENSOR-DATA":
      for (key, value) in json["data"] as? [String: Any] ?? [:] {
        if let string = value as? String { sensors[key] = string }
      }
      lastUpdate = .now
    default:
      break
    }
  }

  func requestEverything() {
    request("REQUEST-CURRENT-STATE")
    request("REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA")
  }

  func setPower(_ on: Bool) { set(["fpwr": on ? "ON" : "OFF"]) }

  func setAuto(_ on: Bool) { set(["auto": on ? "ON" : "OFF", "fpwr": "ON"]) }

  func setSpeed(_ speed: Int) {
    set(["fpwr": "ON", "auto": "OFF", "fnsp": String(format: "%04d", speed)])
  }

  func setNightMode(_ on: Bool) { set(["nmod": on ? "ON" : "OFF"]) }

  func setAirflow(_ airflow: Airflow) { set(["fdir": airflow.rawValue]) }

  func setOscillation(_ on: Bool) {
    guard on else { return set(["oson": "OFF"]) }
    setOscillationWidth(oscillationWidth ?? 90)
  }

  /// Keeps the current centre of the sweep and widens or narrows it around it.
  func setOscillationWidth(_ width: Int) {
    let low = state["osal"].flatMap(Int.init) ?? 135
    let high = state["osau"].flatMap(Int.init) ?? 225
    let centre = (low + high) / 2
    var newLow = max(5, centre - width / 2)
    var newHigh = newLow + width
    if newHigh > 355 {
      newHigh = 355
      newLow = newHigh - width
    }
    set([
      "oson": "ON", "fpwr": "ON", "ancp": "CUST",
      "osal": String(format: "%04d", newLow), "osau": String(format: "%04d", newHigh),
    ])
  }

  func setSleepTimer(_ minutes: Int?) {
    set(["sltm": minutes.map { String(format: "%04d", $0) } ?? "OFF"])
  }

  private func set(_ data: [String: String]) {
    guard let client, let config else { return }
    // Optimistic: the device confirms with a STATE-CHANGE a moment later.
    state.merge(data) { $1 }
    if data["auto"] == "ON" { state["fnsp"] = "AUTO" }
    send(client, config, ["msg": "STATE-SET", "mode-reason": "LAPP", "data": data])
  }

  private func request(_ message: String) {
    guard let client, let config else { return }
    send(client, config, ["msg": message])
  }

  private func send(_ client: MQTTClient, _ config: DeviceConfig, _ body: [String: Any]) {
    var body = body
    body["time"] = Date.now.ISO8601Format()
    guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
    client.publish(topic: "\(config.topicRoot)/\(config.serial)/command", payload: payload)
  }
}
