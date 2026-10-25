import DysonKit
import Foundation
import UserNotifications

/// Turns device updates into notifications. Each alert fires once per episode:
/// air quality after it stays bad for a while, filters once they cross the
/// limit, faults when a new code appears.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  static let badAirDelay: TimeInterval = 5 * 60
  static let filterLimit = 10

  private let preferences: Preferences
  private let center = UNUserNotificationCenter.current()
  private var badAirSince: [String: Date] = [:]
  private var badAirNotified: Set<String> = []
  private var knownFaults: [String: Set<String>] = [:]

  init(preferences: Preferences) {
    self.preferences = preferences
    super.init()
    center.delegate = self
  }

  func requestPermission() {
    center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  func handle(_ device: DysonDevice, change: DeviceSnapshot.Change) {
    switch change {
    case .sensors: checkAir(device)
    case .state: checkFilters(device)
    case .faults: checkFaults(device)
    case .none: break
    }
  }

  private func checkAir(_ device: DysonDevice, now: Date = .now) {
    let serial = device.id
    guard let worst = device.snapshot.worstReading, worst.level >= preferences.airQualityThreshold else {
      badAirSince[serial] = nil
      badAirNotified.remove(serial)
      return
    }
    let since = badAirSince[serial] ?? now
    badAirSince[serial] = since
    guard preferences.notifyAirQuality, !badAirNotified.contains(serial),
      now.timeIntervalSince(since) >= Self.badAirDelay
    else { return }
    badAirNotified.insert(serial)
    let value = "\(worst.pollutant.title) \(worst.pollutant.format(worst.value)) \(worst.pollutant.unit)"
    post(
      id: "air.\(serial)",
      title: String(localized: "Air quality in \(device.name): \(worst.level.title)"),
      body: device.snapshot.isOn
        ? String(localized: "\(value). The purifier is running.")
        : String(localized: "\(value). The purifier is off — turn it on from the menu bar.")
    )
  }

  private func checkFilters(_ device: DysonDevice) {
    let filters: [(key: String, percent: Int?, title: String)] = [
      ("hepa", device.snapshot.hepaFilter, String(localized: "HEPA filter")),
      ("carbon", device.snapshot.carbonFilter, String(localized: "Carbon filter")),
    ]
    for filter in filters {
      guard let percent = filter.percent else { continue }
      let flag = "filterNotified.\(device.id).\(filter.key)"
      // Reset once a new filter is in, so the next replacement is announced again.
      guard percent <= Self.filterLimit else {
        UserDefaults.standard.removeObject(forKey: flag)
        continue
      }
      guard preferences.notifyFilter, !UserDefaults.standard.bool(forKey: flag) else { continue }
      UserDefaults.standard.set(true, forKey: flag)
      post(
        id: flag,
        title: String(localized: "\(filter.title) in \(device.name) is almost used up"),
        body: String(localized: "\(percent) % left. Order a replacement soon.")
      )
    }
  }

  private func checkFaults(_ device: DysonDevice) {
    var codes = Set(device.snapshot.faults.keys)
    if let warning = device.snapshot.warningCode { codes.insert(warning) }
    let new = codes.subtracting(knownFaults[device.id] ?? [])
    knownFaults[device.id] = codes
    guard preferences.notifyFaults, !new.isEmpty else { return }
    let list = new.sorted().joined(separator: ", ")
    post(
      id: "fault.\(device.id).\(list)",
      title: String(localized: "\(device.name) reports a problem"),
      body: String(localized: "Fault code \(list). The MyDyson app explains what to do.")
    )
  }

  private func post(id: String, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
  }

  /// A menu bar app counts as frontmost, so without this macOS swallows the banner.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
