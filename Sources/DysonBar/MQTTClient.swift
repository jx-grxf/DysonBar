import Foundation
import Network

/// Just enough MQTT 3.1.1 for a Dyson: connect with username/password,
/// subscribe, publish, keepalive. The device broker never sends retained
/// messages or QoS 2, so neither is handled.
final class MQTTClient: @unchecked Sendable {
  enum Event {
    /// Carries the resolved IP so the next launch can skip discovery.
    case connected(remoteHost: String?)
    case message(topic: String, payload: Data)
    case disconnected(String)
  }

  private let endpoint: NWEndpoint
  private let username: String
  private let password: String
  private let queue = DispatchQueue(label: "DysonBar.mqtt")
  private var connection: NWConnection?
  private var buffer = Data()
  private var nextPacketID: UInt16 = 1
  private var keepaliveTimer: DispatchSourceTimer?
  private var handshakeTimeout: DispatchWorkItem?
  private var pendingSubscriptions: [String] = []
  private var isOpen = false

  var onEvent: (@Sendable (Event) -> Void)?

  init(endpoint: NWEndpoint, username: String, password: String) {
    self.endpoint = endpoint
    self.username = username
    self.password = password
  }

  func start(subscribing topics: [String]) {
    queue.async { [self] in
      pendingSubscriptions = topics
      let connection = NWConnection(to: endpoint, using: .tcp)
      self.connection = connection
      connection.stateUpdateHandler = { [weak self] state in
        guard let self else { return }
        switch state {
        case .ready:
          self.send(self.connectPacket())
          self.receive()
        case .failed(let error):
          self.close(reason: error.localizedDescription)
        case .waiting(let error):
          self.close(reason: error.localizedDescription)
        default:
          break
        }
      }
      connection.start(queue: queue)

      // NWConnection can sit in .preparing forever (e.g. a Bonjour endpoint on
      // the wrong interface), so a missing CONNACK counts as a failure.
      let timeout = DispatchWorkItem { [weak self] in
        guard let self, !self.isOpen else { return }
        self.close(reason: "Zeitüberschreitung")
      }
      handshakeTimeout = timeout
      queue.asyncAfter(deadline: .now() + 6, execute: timeout)
    }
  }

  func stop() {
    queue.async { [self] in
      if isOpen { send(Data([0xE0, 0x00])) }
      close(reason: "stopped", notify: false)
    }
  }

  func publish(topic: String, payload: Data) {
    queue.async { [self] in
      guard isOpen else { return }
      var body = Self.encode(string: topic)
      body.append(contentsOf: packetID().bigEndianBytes)
      body.append(payload)
      // QoS 1, like the official app; the PUBACK is read and ignored.
      send(Self.packet(type: 0x32, body: body))
    }
  }

  private func close(reason: String, notify: Bool = true) {
    guard connection != nil else { return }
    handshakeTimeout?.cancel()
    handshakeTimeout = nil
    keepaliveTimer?.cancel()
    keepaliveTimer = nil
    connection?.stateUpdateHandler = nil
    connection?.cancel()
    connection = nil
    buffer.removeAll()
    isOpen = false
    if notify { onEvent?(.disconnected(reason)) }
  }

  private func send(_ data: Data) {
    connection?.send(content: data, completion: .contentProcessed { [weak self] error in
      if let error { self?.close(reason: error.localizedDescription) }
    })
  }

  private func receive() {
    connection?.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
      guard let self else { return }
      if let data, !data.isEmpty {
        self.buffer.append(data)
        self.drainBuffer()
      }
      if let error {
        self.close(reason: error.localizedDescription)
      } else if isComplete {
        self.close(reason: "Gerät hat die Verbindung beendet")
      } else {
        self.receive()
      }
    }
  }

  private func drainBuffer() {
    while let (header, body, consumed) = Self.nextPacket(in: buffer) {
      buffer.removeFirst(consumed)
      handle(header: header, body: body)
    }
  }

  private func handle(header: UInt8, body: Data) {
    switch header >> 4 {
    case 2:  // CONNACK
      let code = body.count >= 2 ? body[body.startIndex + 1] : 0xFF
      guard code == 0 else {
        close(reason: code == 4 || code == 5 ? "Zugangsdaten abgelehnt" : "CONNACK \(code)")
        return
      }
      isOpen = true
      handshakeTimeout?.cancel()
      startKeepalive()
      subscribe(pendingSubscriptions)
      onEvent?(.connected(remoteHost: remoteHost()))
    case 3:  // PUBLISH
      let qos = (header >> 1) & 0x03
      guard body.count >= 2 else { return }
      let topicLength = Int(body[body.startIndex]) << 8 | Int(body[body.startIndex + 1])
      var offset = body.startIndex + 2 + topicLength
      guard offset <= body.endIndex else { return }
      let topic = String(decoding: body[(body.startIndex + 2)..<offset], as: UTF8.self)
      if qos > 0 {
        let id = body[offset..<min(offset + 2, body.endIndex)]
        send(Data([0x40, 0x02]) + id)
        offset += 2
      }
      onEvent?(.message(topic: topic, payload: Data(body[min(offset, body.endIndex)...])))
    default:
      break  // SUBACK, PUBACK, PINGRESP
    }
  }

  private func remoteHost() -> String? {
    guard case .hostPort(let host, _) = connection?.currentPath?.remoteEndpoint else { return nil }
    switch host {
    case .ipv4(let address): return "\(address)".components(separatedBy: "%").first
    case .ipv6(let address): return "\(address)".components(separatedBy: "%").first
    case .name(let name, _): return name
    @unknown default: return nil
    }
  }

  private func subscribe(_ topics: [String]) {
    guard !topics.isEmpty else { return }
    var body = Data(packetID().bigEndianBytes)
    for topic in topics {
      body.append(Self.encode(string: topic))
      body.append(0x00)
    }
    send(Self.packet(type: 0x82, body: body))
  }

  private func startKeepalive() {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + 30, repeating: 30)
    timer.setEventHandler { [weak self] in self?.send(Data([0xC0, 0x00])) }
    timer.resume()
    keepaliveTimer = timer
  }

  private func connectPacket() -> Data {
    var body = Self.encode(string: "MQTT")
    body.append(0x04)  // protocol level 3.1.1
    body.append(0xC2)  // username, password, clean session
    body.append(contentsOf: UInt16(60).bigEndianBytes)
    body.append(Self.encode(string: "dysonbar-\(UUID().uuidString.prefix(8))"))
    body.append(Self.encode(string: username))
    body.append(Self.encode(string: password))
    return Self.packet(type: 0x10, body: body)
  }

  private func packetID() -> UInt16 {
    defer { nextPacketID = nextPacketID == .max ? 1 : nextPacketID + 1 }
    return nextPacketID
  }

  private static func encode(string: String) -> Data {
    let bytes = Data(string.utf8)
    return Data(UInt16(bytes.count).bigEndianBytes) + bytes
  }

  private static func packet(type: UInt8, body: Data) -> Data {
    var data = Data([type])
    var length = body.count
    repeat {
      var byte = UInt8(length % 128)
      length /= 128
      if length > 0 { byte |= 0x80 }
      data.append(byte)
    } while length > 0
    return data + body
  }

  private static func nextPacket(in buffer: Data) -> (UInt8, Data, Int)? {
    guard buffer.count >= 2 else { return nil }
    let start = buffer.startIndex
    var multiplier = 1
    var length = 0
    var index = start + 1
    while true {
      guard index < buffer.endIndex, index - start <= 4 else { return nil }
      let byte = buffer[index]
      length += Int(byte & 0x7F) * multiplier
      multiplier *= 128
      index += 1
      if byte & 0x80 == 0 { break }
    }
    let end = index + length
    guard end <= buffer.endIndex else { return nil }
    return (buffer[start], Data(buffer[index..<end]), end - start)
  }
}

private extension UInt16 {
  var bigEndianBytes: [UInt8] { [UInt8(self >> 8), UInt8(self & 0xFF)] }
}
