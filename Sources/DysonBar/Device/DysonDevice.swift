import DysonKit
import Foundation
import Network
import Observation
import os

@MainActor
@Observable
final class DysonDevice: Identifiable {
  enum Connection: Equatable {
    case searching
    case connecting(String)
    case connected(String)
    case offline(String)

    var isConnected: Bool {
      if case .connected = self { return true }
      return false
    }
  }

  static let oscillationWidths = [45, 90, 180, 350]
  static let sleepTimerMinutes = [15, 30, 60, 120, 240, 480]
  static let humidityTargets = [30, 40, 50, 60, 70]

  private(set) var record: DeviceRecord
  private(set) var connection: Connection = .searching
  private(set) var snapshot = DeviceSnapshot()
  /// Bumped on every stored sample so charts redraw; the store itself is not observable.
  private(set) var historyRevision = 0

  @ObservationIgnored let history: HistoryStore
  @ObservationIgnored var onUpdate: ((DysonDevice, DeviceSnapshot.Change) -> Void)?

  @ObservationIgnored private let password: String
  @ObservationIgnored private var client: MQTTClient?
  @ObservationIgnored private var clientGeneration: UUID?
  @ObservationIgnored private var browser: NWBrowser?
  @ObservationIgnored private var retryDelay: Duration = .seconds(2)
  @ObservationIgnored private var retryTask: Task<Void, Never>?
  @ObservationIgnored private var pollTask: Task<Void, Never>?
  @ObservationIgnored private var pendingRoutes: [Route] = []
  @ObservationIgnored private var isStopped = true
  @ObservationIgnored private let log = Logger(subsystem: "at.johannesgrof.DysonBar", category: "connection")

  init(record: DeviceRecord, password: String) {
    self.record = record
    self.password = password
    id = record.serial
    history = HistoryStore(serial: record.serial)
  }

  let id: String
  var name: String { record.displayName }
  var capabilities: Capabilities { snapshot.capabilities }

  func update(record: DeviceRecord) {
    let needsReconnect = record.host != self.record.host
    self.record = record
    if needsReconnect { reconnect() }
  }

  // MARK: Lifecycle

  func start() {
    isStopped = false
    retryDelay = .seconds(2)
    connect()
  }

  func stop() {
    isStopped = true
    teardown()
  }

  func reconnect() {
    guard !isStopped else { return }
    retryDelay = .seconds(2)
    connect()
  }

  private enum Route {
    case host(String)
    case bonjour
  }

  private var lastHostKey: String { "lastHost.\(record.serial)" }

  /// Cheapest first: the address that worked last time, then the serial as a
  /// hostname, which most home routers resolve from DHCP and which fails fast
  /// when they don't, then Bonjour, whose service endpoint can take seconds.
  private func routes() -> [Route] {
    if let host = record.host, !host.isEmpty { return [.host(host)] }
    var routes: [Route] = []
    if let last = UserDefaults.standard.string(forKey: lastHostKey) {
      routes.append(.host(last))
    }
    routes.append(.host(record.serial.lowercased()))
    routes.append(.bonjour)
    return routes
  }

  private func connect() {
    teardown()
    pendingRoutes = routes()
    tryNextRoute(lastError: nil)
  }

  private func tryNextRoute(lastError: String?) {
    guard !pendingRoutes.isEmpty else {
      log.info("all routes failed: \(lastError ?? "-", privacy: .public)")
      connection = .offline(lastError ?? String(localized: "No response"))
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
    // Devices announce themselves as "<product type>_<serial>", e.g. "438_AB1-EU-XYZ".
    // An exact match keeps other services from catching the MQTT password.
    let expectedName = "\(record.type.prefix(3))_\(record.serial)"
    connection = .searching
    let browser = NWBrowser(for: .bonjour(type: "_dyson_mqtt._tcp", domain: "local."), using: .tcp)
    browser.browseResultsChangedHandler = { [weak self] results, _ in
      let match = results.first {
        if case .service(let name, _, _, _) = $0.endpoint { return name == expectedName }
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
      self.tryNextRoute(lastError: String(localized: "Not found via Bonjour"))
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
    log.info("connecting via \(label, privacy: .public)")
    connection = .connecting(label)
    let root = "\(record.topicRoot)/\(record.serial)"
    // Events from a client that was already replaced must not touch the state.
    let generation = UUID()
    clientGeneration = generation
    let client = MQTTClient(endpoint: endpoint, username: record.serial, password: password) { [weak self] event in
      Task { @MainActor in
        guard let self, self.clientGeneration == generation else { return }
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
    clientGeneration = nil
  }

  private func handle(_ event: MQTTClient.Event, label: String) {
    switch event {
    case .connected(let remoteHost):
      log.info("connected via \(label, privacy: .public)")
      if let remoteHost { UserDefaults.standard.set(remoteHost, forKey: lastHostKey) }
      connection = .connected(remoteHost ?? label)
      pendingRoutes = []
      retryDelay = .seconds(2)
      requestEverything()
      request("REQUEST-CURRENT-FAULTS")
      pollTask = Task { [weak self] in
        var tick = 0
        while !Task.isCancelled {
          try? await Task.sleep(for: .seconds(30))
          guard let self, !Task.isCancelled else { return }
          tick += 1
          self.request("REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA")
          if tick % 10 == 0 { self.request("REQUEST-CURRENT-FAULTS") }
        }
      }
    case .message(_, let payload):
      let change = snapshot.apply(payload)
      if change == .sensors, let date = snapshot.lastUpdate {
        let before = history.samples.count
        history.record(Sample(snapshot: snapshot, date: date))
        if history.samples.count != before { historyRevision += 1 }
      }
      if change != .none { onUpdate?(self, change) }
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
    guard !isStopped else { return }
    retryTask?.cancel()
    let delay = retryDelay
    retryDelay = min(retryDelay * 2, .seconds(30))
    retryTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.connect()
    }
  }

  // MARK: Commands

  func requestEverything() {
    request("REQUEST-CURRENT-STATE")
    request("REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA")
  }

  func setPower(_ on: Bool) { set(DeviceCommand.power(on)) }
  func setAuto(_ on: Bool) { set(DeviceCommand.auto(on)) }
  func setSpeed(_ speed: Int) { set(DeviceCommand.speed(speed)) }
  func setNightMode(_ on: Bool) { set(DeviceCommand.nightMode(on)) }
  func setAirflow(front: Bool) { set(DeviceCommand.airflow(front: front)) }
  func setSleepTimer(_ minutes: Int?) { set(DeviceCommand.sleepTimer(minutes)) }
  func setHeating(_ on: Bool) { set(DeviceCommand.heating(on)) }
  func setHeatingTarget(_ celsius: Double) { set(DeviceCommand.heatingTarget(celsius: celsius)) }
  func setHumidifier(_ on: Bool) { set(DeviceCommand.humidifier(on)) }
  func setHumidityAuto(_ on: Bool) { set(DeviceCommand.humidityAuto(on)) }
  func setHumidityTarget(_ percent: Int) { set(DeviceCommand.humidityTarget(percent)) }

  func setOscillation(_ on: Bool) {
    guard on else { return set(["oson": "OFF"]) }
    guard capabilities.contains(.oscillationAngles) else { return set(["oson": "ON"]) }
    setOscillationWidth(snapshot.oscillationWidth ?? 90)
  }

  func setOscillationWidth(_ width: Int) {
    set(DeviceCommand.oscillation(width: width, current: snapshot.state))
  }

  private func set(_ data: [String: String]) {
    guard let client else { return }
    // Optimistic: the device confirms with a STATE-CHANGE a moment later.
    snapshot.state.merge(data) { $1 }
    if data["auto"] == "ON" { snapshot.state["fnsp"] = "AUTO" }
    send(client, ["msg": "STATE-SET", "mode-reason": "LAPP", "data": data])
  }

  private func request(_ message: String) {
    guard let client else { return }
    send(client, ["msg": message])
  }

  private func send(_ client: MQTTClient, _ body: [String: Any]) {
    var body = body
    body["time"] = Date.now.ISO8601Format()
    guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }
    client.publish(topic: "\(record.topicRoot)/\(record.serial)/command", payload: payload)
  }
}
