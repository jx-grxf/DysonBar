import AppKit
import DysonKit
import Observation
import ServiceManagement

enum MenuBarStyle: String, CaseIterable, Identifiable {
  case icon, status, level, temperature

  var id: String { rawValue }

  var title: String {
    switch self {
    case .icon: String(localized: "Icon only")
    case .status: String(localized: "Icon with colour dot")
    case .level: String(localized: "Air quality")
    case .temperature: String(localized: "Temperature")
    }
  }
}

enum AppLanguage: String, CaseIterable, Identifiable {
  case system, english = "en", german = "de"

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: String(localized: "System")
    // Each language is named in itself, so it can be found from any setting.
    case .english: "English"
    case .german: "Deutsch"
    }
  }
}

@MainActor
@Observable
final class Preferences {
  private let defaults = UserDefaults.standard

  var menuBarStyle: MenuBarStyle {
    didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") }
  }

  var notifyAirQuality: Bool {
    didSet { defaults.set(notifyAirQuality, forKey: "notifyAirQuality") }
  }

  var airQualityThreshold: AirLevel {
    didSet { defaults.set(airQualityThreshold.rawValue, forKey: "airQualityThreshold") }
  }

  var notifyFilter: Bool {
    didSet { defaults.set(notifyFilter, forKey: "notifyFilter") }
  }

  var notifyFaults: Bool {
    didSet { defaults.set(notifyFaults, forKey: "notifyFaults") }
  }

  var hasCompletedOnboarding: Bool {
    didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
  }

  init() {
    defaults.register(defaults: [
      "notifyAirQuality": true,
      "airQualityThreshold": AirLevel.poor.rawValue,
      "notifyFilter": true,
      "notifyFaults": true,
    ])
    menuBarStyle = MenuBarStyle(rawValue: defaults.string(forKey: "menuBarStyle") ?? "") ?? .status
    notifyAirQuality = defaults.bool(forKey: "notifyAirQuality")
    airQualityThreshold = AirLevel(rawValue: defaults.integer(forKey: "airQualityThreshold")) ?? .poor
    notifyFilter = defaults.bool(forKey: "notifyFilter")
    notifyFaults = defaults.bool(forKey: "notifyFaults")
    hasCompletedOnboarding = defaults.bool(forKey: "hasCompletedOnboarding")
  }

  // MARK: Launch at login

  var launchAtLogin: Bool {
    get {
      access(keyPath: \.launchAtLogin)
      return SMAppService.mainApp.status == .enabled
    }
    set {
      withMutation(keyPath: \.launchAtLogin) {
        do {
          if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
          NSSound.beep()
        }
      }
    }
  }

  // MARK: Language

  /// Only the app's own domain counts; `UserDefaults.standard` would also
  /// return the system-wide list.
  var language: AppLanguage {
    let domain = Bundle.main.bundleIdentifier.flatMap { defaults.persistentDomain(forName: $0) }
    guard let code = (domain?["AppleLanguages"] as? [String])?.first else { return .system }
    return AppLanguage(rawValue: String(code.prefix(2))) ?? .system
  }

  /// macOS reads the language once at launch, so a change needs a restart.
  func switchLanguage(to language: AppLanguage) {
    guard language != self.language else { return }
    if language == .system {
      defaults.removeObject(forKey: "AppleLanguages")
    } else {
      defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
    defaults.synchronize()
    Self.relaunch()
  }

  static func relaunch() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "sleep 0.6; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
    try? process.run()
    NSApp.terminate(nil)
  }
}
