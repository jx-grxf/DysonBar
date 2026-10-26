import AppKit
import DysonKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
  case general, devices, notifications, updates, about

  var id: Self { self }

  var title: String {
    switch self {
    case .general: String(localized: "General")
    case .devices: String(localized: "Devices")
    case .notifications: String(localized: "Notifications")
    case .updates: String(localized: "Updates")
    case .about: String(localized: "About")
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .devices: "air.purifier"
    case .notifications: "bell.badge"
    case .updates: "arrow.triangle.2.circlepath"
    case .about: "info.circle"
    }
  }
}

@MainActor
@Observable
final class SettingsNavigation {
  static let shared = SettingsNavigation()
  var selectedTab: SettingsTab? = .general
  private init() {}
}

enum AppVersion {
  static var short: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev" }
  static var build: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }
}

struct SettingsView: View {
  @State private var navigation = SettingsNavigation.shared

  var body: some View {
    NavigationSplitView(columnVisibility: .constant(.all)) {
      List(selection: $navigation.selectedTab) {
        ForEach(SettingsTab.allCases) { tab in
          Label(tab.title, systemImage: tab.systemImage)
            .tag(tab)
        }
      }
      .listStyle(.sidebar)
      .scrollEdgeEffectSoftIfAvailable()
      .safeAreaInset(edge: .bottom, alignment: .leading) {
        Text("DysonBar \(AppVersion.short)")
          .font(.footnote.monospaced())
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 18)
          .padding(.bottom, 12)
      }
      .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      let tab = navigation.selectedTab ?? .general
      Group {
        switch tab {
        case .general: GeneralPane()
        case .devices: DevicesPane()
        case .notifications: NotificationsPane()
        case .updates: UpdatesPane()
        case .about: AboutPane()
        }
      }
      .navigationTitle(tab.title)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    .navigationSplitViewStyle(.balanced)
    .frame(minWidth: 660, minHeight: 480)
  }
}

extension View {
  @ViewBuilder
  func scrollEdgeEffectSoftIfAvailable() -> some View {
    if #available(macOS 26.0, *) {
      scrollEdgeEffectStyle(.soft, for: .all)
    } else {
      self
    }
  }

  func settingsForm() -> some View {
    formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .contentMargins(.top, 8, for: .scrollContent)
      .toggleStyle(.switch)
  }
}

/// Toggle label with the explanation underneath, the way System Settings does it.
struct SettingLabel: View {
  let title: String
  let detail: String

  init(_ title: String, _ detail: String) {
    self.title = title
    self.detail = detail
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - General

private struct GeneralPane: View {
  @Environment(AppModel.self) private var model
  @State private var language: AppLanguage = .system
  @State private var confirmLanguage: AppLanguage?

  var body: some View {
    @Bindable var preferences = model.preferences
    Form {
      Section {
        Toggle(isOn: $preferences.launchAtLogin) {
          SettingLabel(String(localized: "Open at login"), String(localized: "DysonBar starts with your Mac and stays in the menu bar."))
        }
        Toggle(isOn: $preferences.showInDock) {
          SettingLabel(String(localized: "Show in Dock"), String(localized: "Adds a Dock icon that opens these settings. DysonBar always stays in the menu bar."))
        }
      }

      Section(String(localized: "Menu Bar")) {
        Picker(String(localized: "Show"), selection: $preferences.menuBarStyle) {
          ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
        }
        Text("The colour dot follows the air quality of the selected device: green is good, red is bad.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(String(localized: "Language")) {
        Picker(String(localized: "Language"), selection: $language) {
          ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
        }
        .onChange(of: language) { _, new in
          if new != model.preferences.language { confirmLanguage = new }
        }
        Text("“System” follows the language in System Settings. Changing it restarts DysonBar.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .settingsForm()
    .onAppear { language = model.preferences.language }
    .confirmationDialog(
      String(localized: "Restart DysonBar?"),
      isPresented: Binding(get: { confirmLanguage != nil }, set: { if !$0 { confirmLanguage = nil } })
    ) {
      Button(String(localized: "Restart")) {
        if let confirmLanguage { model.preferences.switchLanguage(to: confirmLanguage) }
      }
      Button(String(localized: "Cancel"), role: .cancel) {
        language = model.preferences.language
      }
    } message: {
      Text("The new language takes effect after a restart.")
    }
  }
}

// MARK: - Devices

private struct DevicesPane: View {
  @Environment(AppModel.self) private var model
  @State private var addingDevice = false
  @State private var removing: String?

  var body: some View {
    let store = model.store
    Form {
      if store.devices.isEmpty && store.missingPasswords.isEmpty {
        Section {
          ContentUnavailableView {
            Label(String(localized: "No Devices"), systemImage: "air.purifier")
          } description: {
            Text("Sign in with your MyDyson account to add your purifiers.")
          }
        }
      }

      ForEach(store.devices) { device in
        DeviceSection(device: device) { removing = device.id }
      }

      ForEach(store.missingPasswords, id: \.serial) { record in
        Section(record.displayName) {
          LabeledContent(String(localized: "Status")) {
            Label(String(localized: "Sign in again"), systemImage: "key.fill")
              .foregroundStyle(Tokens.level(.poor))
          }
          Button(String(localized: "Remove"), role: .destructive) { removing = record.serial }
        }
      }

      Section {
        HStack {
          Button(String(localized: "Add Devices…")) { addingDevice = true }
          Spacer()
          Text("Signs in to MyDyson once and adds every purifier on the account.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .settingsForm()
    .sheet(isPresented: $addingDevice) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Add Devices")
          .font(.title3.weight(.semibold))
          .padding([.top, .horizontal], 20)
        SignInFlow { _ in addingDevice = false }
          .padding(.bottom, 20)
        HStack {
          Spacer()
          Button(String(localized: "Cancel")) { addingDevice = false }
            .keyboardShortcut(.cancelAction)
        }
        .padding([.horizontal, .bottom], 20)
      }
      .frame(width: 460)
      .environment(model)
    }
    .confirmationDialog(
      String(localized: "Remove this device?"),
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    ) {
      Button(String(localized: "Remove"), role: .destructive) {
        if let removing { model.store.remove(removing) }
      }
    } message: {
      Text("DysonBar deletes its Wi-Fi key and history. The device itself and your MyDyson account stay as they are.")
    }
  }
}

private struct DeviceSection: View {
  let device: DysonDevice
  let onRemove: () -> Void
  @Environment(AppModel.self) private var model
  @State private var name = ""
  @State private var host = ""

  var body: some View {
    Section {
      TextField(String(localized: "Name"), text: $name)
        .onSubmit(save)
      LabeledContent(String(localized: "Model"), value: "\(device.record.productName) (\(device.record.model ?? device.record.type))")
      LabeledContent(String(localized: "Serial number")) {
        Text(device.record.serial).textSelection(.enabled).monospaced()
      }
      LabeledContent(String(localized: "Connection")) {
        Text(connectionText).foregroundStyle(.secondary)
      }
      TextField(text: $host, prompt: Text("Automatic")) {
        SettingLabel(String(localized: "Fixed address"), String(localized: "Only if the device isn't found: its IP address from your router."))
      }
      .onSubmit(save)
      HStack {
        Button(String(localized: "Reconnect")) { device.reconnect() }
        Spacer()
        Button(String(localized: "Remove…"), role: .destructive, action: onRemove)
      }
    } header: {
      HStack {
        Text(device.name)
        if model.store.selected?.id == device.id {
          Text("In menu bar")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Tokens.hover, in: .capsule)
        } else {
          Button(String(localized: "Show in Menu Bar")) { model.store.selectedID = device.id }
            .buttonStyle(.link)
            .font(.caption)
        }
      }
    }
    .onAppear {
      name = device.record.name ?? ""
      host = device.record.host ?? ""
    }
    .onChange(of: name) { _, _ in save() }
    .onChange(of: host) { _, _ in saveHostLater() }
  }

  private var connectionText: String {
    switch device.connection {
    case .connected(let address): String(localized: "Connected via \(address)")
    case .connecting: String(localized: "Connecting …")
    case .searching: String(localized: "Searching …")
    case .offline(let reason): String(localized: "Offline: \(reason)")
    case .localNetworkDenied: String(localized: "No local network access")
    }
  }

  private func save() {
    var record = device.record
    record.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? record.name : name
    let trimmedHost = host.trimmingCharacters(in: .whitespaces)
    record.host = trimmedHost.isEmpty ? nil : trimmedHost
    guard record != device.record else { return }
    model.store.update(record)
  }

  /// Typing an address would otherwise reconnect on every keystroke.
  private func saveHostLater() {
    let snapshot = host
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      if snapshot == host { save() }
    }
  }
}

// MARK: - Notifications

private struct NotificationsPane: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var preferences = model.preferences
    Form {
      Section {
        Toggle(isOn: $preferences.notifyAirQuality) {
          SettingLabel(
            String(localized: "Bad air"),
            String(localized: "When the air stays at or above the chosen level for five minutes."))
        }
        Picker(String(localized: "Notify from"), selection: $preferences.airQualityThreshold) {
          ForEach(AirLevel.allCases.dropFirst(), id: \.self) { level in
            Text(level.title).tag(level)
          }
        }
        .disabled(!preferences.notifyAirQuality)
      }
      Section {
        Toggle(isOn: $preferences.notifyFilter) {
          SettingLabel(String(localized: "Filter almost used up"), String(localized: "Once, when a filter drops to 10 %."))
        }
        Toggle(isOn: $preferences.notifyFaults) {
          SettingLabel(String(localized: "Device faults"), String(localized: "When the purifier reports a new fault or warning code."))
        }
      }
      Section {
        Button(String(localized: "Open Notification Settings…")) {
          NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
        }
      } footer: {
        Text("If nothing arrives, check that DysonBar is allowed to send notifications.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .settingsForm()
    .onChange(of: preferences.notifyAirQuality) { _, on in if on { model.notifier.requestPermission() } }
    .onChange(of: preferences.notifyFilter) { _, on in if on { model.notifier.requestPermission() } }
    .onChange(of: preferences.notifyFaults) { _, on in if on { model.notifier.requestPermission() } }
  }
}

// MARK: - Updates

private struct UpdatesPane: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var updater = model.updater
    Form {
      if updater.isAvailable {
        Section {
          Toggle(isOn: $updater.automaticallyChecks) {
            SettingLabel(String(localized: "Check for updates automatically"), String(localized: "Once a day. Updates are signed and installed only after you confirm."))
          }
          LabeledContent(String(localized: "Last checked")) {
            Text(updater.lastCheck.map { $0.formatted(.relative(presentation: .named)) } ?? String(localized: "Never"))
              .foregroundStyle(.secondary)
          }
          Button(String(localized: "Check Now")) { updater.checkNow() }
            .disabled(!updater.canCheck)
        }
      } else {
        Section {
          Text("This build has no update feed. Releases from GitHub or Homebrew update themselves.")
            .foregroundStyle(.secondary)
        }
      }
      Section {
        LabeledContent(String(localized: "Version"), value: "\(AppVersion.short) (\(AppVersion.build))")
        Link(String(localized: "Release notes on GitHub"), destination: URL(string: "https://github.com/jx-grxf/DysonBar/releases")!)
      }
    }
    .settingsForm()
  }
}

// MARK: - About

private struct AboutPane: View {
  var body: some View {
    Form {
      Section {
        HStack(spacing: 16) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
          VStack(alignment: .leading, spacing: 3) {
            Text("DysonBar")
              .font(.title2.weight(.semibold))
            Text("Version \(AppVersion.short)")
              .font(.callout.monospacedDigit())
              .foregroundStyle(.secondary)
            Text("Your Dyson purifier in the menu bar, over your own Wi-Fi.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 6)
      }
      Section {
        Link(String(localized: "Source code on GitHub"), destination: URL(string: "https://github.com/jx-grxf/DysonBar")!)
        Link(String(localized: "Report a problem"), destination: URL(string: "https://github.com/jx-grxf/DysonBar/issues/new")!)
      }
      Section {
        Text("DysonBar is an independent open-source project. It is not affiliated with, endorsed or sponsored by Dyson. Dyson is a trademark of Dyson Technology Limited.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Made by Johannes Grof · MIT License")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .settingsForm()
  }
}
