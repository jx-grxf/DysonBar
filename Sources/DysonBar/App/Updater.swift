import Observation
import Sparkle

/// Sparkle only runs in a bundle that names a feed; local `swift run` builds
/// have none and simply show updates as unavailable.
@MainActor
@Observable
final class Updater {
  @ObservationIgnored private let controller: SPUStandardUpdaterController?
  private(set) var canCheck = false
  @ObservationIgnored private var observation: NSKeyValueObservation?

  init() {
    guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
      controller = nil
      return
    }
    let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    self.controller = controller
    observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
      let value = updater.canCheckForUpdates
      Task { @MainActor in self?.canCheck = value }
    }
  }

  var isAvailable: Bool { controller != nil }

  var automaticallyChecks: Bool {
    get {
      access(keyPath: \.automaticallyChecks)
      return controller?.updater.automaticallyChecksForUpdates ?? false
    }
    set {
      withMutation(keyPath: \.automaticallyChecks) {
        controller?.updater.automaticallyChecksForUpdates = newValue
      }
    }
  }

  var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

  func checkNow() {
    controller?.checkForUpdates(nil)
  }
}
