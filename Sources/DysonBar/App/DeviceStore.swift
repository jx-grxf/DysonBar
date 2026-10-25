import AppKit
import DysonKit
import Network
import Observation

/// All configured devices and which one the panel shows.
@MainActor
@Observable
final class DeviceStore {
  private(set) var devices: [DysonDevice] = []
  /// Saved devices whose Keychain entry is gone; they need a new sign-in.
  private(set) var missingPasswords: [DeviceRecord] = []

  var selectedID: String? {
    didSet { UserDefaults.standard.set(selectedID, forKey: "selectedDevice") }
  }

  var selected: DysonDevice? {
    devices.first { $0.id == selectedID } ?? devices.first
  }

  var isEmpty: Bool { devices.isEmpty && missingPasswords.isEmpty }

  @ObservationIgnored var onDeviceUpdate: ((DysonDevice, DeviceSnapshot.Change) -> Void)?
  @ObservationIgnored private let pathMonitor = NWPathMonitor()
  @ObservationIgnored private var lastPath: NWPath.Status?
  @ObservationIgnored private var reconnectTask: Task<Void, Never>?

  init() {
    selectedID = UserDefaults.standard.string(forKey: "selectedDevice")
    load()
    observeSystem()
  }

  private func load() {
    let records = DeviceStorage.load()
    migrateLegacyHost(to: records.first)
    for record in records {
      if let password = DevicePasswords.read(serial: record.serial) {
        devices.append(makeDevice(record, password: password))
      } else {
        missingPasswords.append(record)
      }
    }
  }

  func startAll() {
    devices.forEach { $0.start() }
  }

  /// Merges the devices from a sign-in. Local edits (name, fixed address) survive.
  func add(_ cloudDevices: [DysonCloud.Device]) throws {
    for cloud in cloudDevices {
      try DevicePasswords.save(cloud.password, serial: cloud.record.serial)
      missingPasswords.removeAll { $0.serial == cloud.record.serial }
      if let existing = devices.firstIndex(where: { $0.id == cloud.record.serial }) {
        devices[existing].stop()
        var record = cloud.record
        record.host = devices[existing].record.host
        devices[existing] = makeDevice(record, password: cloud.password)
        devices[existing].start()
      } else {
        let device = makeDevice(cloud.record, password: cloud.password)
        devices.append(device)
        device.start()
      }
    }
    if selectedID == nil { selectedID = devices.first?.id }
    try save()
  }

  func remove(_ serial: String) {
    if let index = devices.firstIndex(where: { $0.id == serial }) {
      devices[index].stop()
      devices[index].history.delete()
      devices.remove(at: index)
    }
    missingPasswords.removeAll { $0.serial == serial }
    DevicePasswords.delete(serial: serial)
    UserDefaults.standard.removeObject(forKey: "lastHost.\(serial)")
    if selectedID == serial { selectedID = devices.first?.id }
    try? save()
  }

  func update(_ record: DeviceRecord) {
    devices.first { $0.id == record.serial }?.update(record: record)
    try? save()
  }

  private func save() throws {
    try DeviceStorage.save(devices.map(\.record) + missingPasswords)
  }

  private func makeDevice(_ record: DeviceRecord, password: String) -> DysonDevice {
    let device = DysonDevice(record: record, password: password)
    device.onUpdate = { [weak self] device, change in self?.onDeviceUpdate?(device, change) }
    return device
  }

  /// Before multi-device support the last address was stored under one key.
  private func migrateLegacyHost(to record: DeviceRecord?) {
    let defaults = UserDefaults.standard
    guard let record, let host = defaults.string(forKey: "lastHost") else { return }
    if defaults.string(forKey: "lastHost.\(record.serial)") == nil {
      defaults.set(host, forKey: "lastHost.\(record.serial)")
    }
    defaults.removeObject(forKey: "lastHost")
  }

  /// Wake from sleep and network switches both leave sockets that look open
  /// but are dead, so every device reconnects right away instead of waiting
  /// for the keepalive to notice.
  private func observeSystem() {
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      Task { @MainActor in self?.reconnectAll() }
    }
    pathMonitor.pathUpdateHandler = { [weak self] path in
      Task { @MainActor in
        guard let self else { return }
        defer { self.lastPath = path.status }
        guard self.lastPath != nil, path.status == .satisfied else { return }
        self.reconnectAll()
      }
    }
    pathMonitor.start(queue: .main)
  }

  private func reconnectAll() {
    reconnectTask?.cancel()
    reconnectTask = Task { [weak self] in
      // Interfaces come up in bursts; one reconnect after they settle is enough.
      try? await Task.sleep(for: .seconds(1.5))
      guard !Task.isCancelled else { return }
      self?.devices.forEach { $0.reconnect() }
    }
  }
}
