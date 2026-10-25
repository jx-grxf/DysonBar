import AppKit
import Observation

/// Owns the long-lived pieces. A singleton because the settings and onboarding
/// windows are AppKit windows outside the SwiftUI scene graph.
@MainActor
@Observable
final class AppModel {
  static let shared = AppModel()

  let store = DeviceStore()
  let preferences = Preferences()
  let updater = Updater()
  @ObservationIgnored private(set) lazy var notifier = Notifier(preferences: preferences)
  @ObservationIgnored private var started = false

  private init() {}

  func start() {
    guard !started else { return }
    started = true
    store.onDeviceUpdate = { [weak self] device, change in
      self?.notifier.handle(device, change: change)
    }
    store.startAll()
    // Opens a window right away, for screenshots: --show settings|devices|onboarding
    let arguments = ProcessInfo.processInfo.arguments
    if let index = arguments.firstIndex(of: "--show"), index + 1 < arguments.count {
      let target = arguments[index + 1]
      if target == "onboarding" {
        WindowPresenter.showOnboarding()
      } else {
        WindowPresenter.showSettings(tab: SettingsTab(rawValue: target) ?? .general)
      }
    }
    if store.isEmpty {
      WindowPresenter.showOnboarding()
    } else if !preferences.hasCompletedOnboarding {
      // Installs from before onboarding existed are already set up.
      preferences.hasCompletedOnboarding = true
    }
  }
}
