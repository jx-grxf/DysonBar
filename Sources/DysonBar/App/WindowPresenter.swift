import AppKit
import SwiftUI

/// A menu bar app has no Dock icon, so a window opened from it stays behind
/// whatever app is active. While one of ours is open the app becomes a regular
/// app, and drops back to accessory when the last one closes, unless the user
/// wants the Dock icon all the time.
@MainActor
enum ActivationPolicy {
  private static var count = 0

  static func enter() {
    count += 1
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
  }

  static func leave() {
    count = max(0, count - 1)
    Task { @MainActor in apply() }
  }

  static func apply() {
    let regular = count > 0 || UserDefaults.standard.bool(forKey: "showInDock")
    NSApp.setActivationPolicy(regular ? .regular : .accessory)
  }
}

/// Clicking the Dock icon opens Settings; there is no main window to show.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    MainActor.assumeIsolated { ActivationPolicy.apply() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    if !hasVisibleWindows { MainActor.assumeIsolated { WindowPresenter.showSettings() } }
    return true
  }
}

@MainActor
enum WindowPresenter {
  private static var settings: HostingWindowController?
  private static var onboarding: HostingWindowController?

  static func showSettings(tab: SettingsTab? = nil) {
    if let tab { SettingsNavigation.shared.selectedTab = tab }
    if settings == nil {
      settings = HostingWindowController(
        title: String(localized: "DysonBar Settings"),
        size: CGSize(width: 720, height: 540),
        minSize: CGSize(width: 660, height: 480),
        autosaveName: "SettingsWindow",
        resizable: true,
        root: SettingsView().environment(AppModel.shared)
      ) { settings = nil }
    }
    settings?.present()
  }

  static func showOnboarding() {
    if onboarding == nil {
      onboarding = HostingWindowController(
        title: String(localized: "Welcome to DysonBar"),
        size: CGSize(width: 520, height: 600),
        minSize: CGSize(width: 520, height: 600),
        autosaveName: nil,
        resizable: false,
        root: OnboardingView().environment(AppModel.shared)
      ) { onboarding = nil }
    }
    onboarding?.present()
  }

  static func closeOnboarding() {
    onboarding?.close()
  }
}

/// Built in AppKit because only a window created with `.fullSizeContentView`
/// gets the Liquid Glass title bar and rounded corners on macOS 26.
@MainActor
final class HostingWindowController: NSWindowController, NSWindowDelegate {
  private let onClose: () -> Void

  init(
    title: String, size: CGSize, minSize: CGSize, autosaveName: String?, resizable: Bool,
    root: some View, onClose: @escaping () -> Void
  ) {
    self.onClose = onClose
    var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    if resizable { style.insert(.resizable) }
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
    super.init(window: window)
    window.title = title
    window.titlebarAppearsTransparent = !resizable
    window.titleVisibility = resizable ? .visible : .hidden
    window.toolbarStyle = .automatic
    window.isMovableByWindowBackground = true
    window.minSize = minSize
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.contentViewController = NSHostingController(rootView: root)
    window.setContentSize(size)
    if let autosaveName, !window.setFrameUsingName(autosaveName) {
      window.center()
    } else if autosaveName == nil {
      window.center()
    }
    if let autosaveName { window.setFrameAutosaveName(autosaveName) }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  func present() {
    let wasVisible = window?.isVisible ?? false
    showWindow(nil)
    window?.makeKeyAndOrderFront(nil)
    if !wasVisible { ActivationPolicy.enter() } else { NSApp.activate() }
  }

  func windowWillClose(_ notification: Notification) {
    ActivationPolicy.leave()
    onClose()
  }
}
