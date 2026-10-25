import DysonKit
import SwiftUI

/// Small and calm on purpose: welcome, sign in, two choices, done.
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var step: Step = .welcome
  @State private var found: [DysonCloud.Device] = []
  @State private var appeared = false

  private enum Step { case welcome, signIn, done }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.top, 44)
        .padding(.bottom, 24)

      Group {
        switch step {
        case .welcome: welcome
        case .signIn:
          SignInFlow { devices in
            found = devices
            go(.done)
          }
        case .done: done
        }
      }
      .transition(.asymmetric(
        insertion: .opacity.combined(with: .offset(x: 24)),
        removal: .opacity.combined(with: .offset(x: -24))))

      Spacer(minLength: 0)
    }
    .frame(width: 520, height: 600)
    .background {
      // Dark display material from the panel, with one cool accent at the top.
      ZStack {
        Color(nsColor: .windowBackgroundColor)
        RadialGradient(
          colors: [Color.accentColor.opacity(0.16), .clear],
          center: .top, startRadius: 10, endRadius: 360)
      }
      .ignoresSafeArea()
    }
    .onAppear { appeared = true }
  }

  private var header: some View {
    VStack(spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .overlay(alignment: .bottomTrailing) {
          if step == .done {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 30))
              .symbolRenderingMode(.palette)
              .foregroundStyle(.white, Tokens.level(.good))
              .transition(.scale.combined(with: .opacity))
          }
        }
      .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
      .opacity(appeared ? 1 : 0)
      .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: appeared)

      VStack(spacing: 6) {
        Text(title)
          .font(.system(size: 24, weight: .semibold))
          .contentTransition(.interpolate)
        Text(subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 400)
      }
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared || reduceMotion ? 0 : 8)
      .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8).delay(0.08), value: appeared)
    }
  }

  private var title: String {
    switch step {
    case .welcome: String(localized: "Your purifier in the menu bar")
    case .signIn: String(localized: "Sign in to MyDyson")
    case .done: found.count == 1 ? String(localized: "\(found[0].record.displayName) is ready") : String(localized: "\(found.count) purifiers are ready")
    }
  }

  private var subtitle: String {
    switch step {
    case .welcome:
      String(localized: "DysonBar shows air quality and controls your Dyson purifier straight from the menu bar, over your own Wi-Fi.")
    case .signIn:
      String(localized: "Only needed once, to fetch the Wi-Fi key of your devices.")
    case .done:
      String(localized: "Find DysonBar in the menu bar, top right. Two quick choices:")
    }
  }

  private var welcome: some View {
    VStack(alignment: .leading, spacing: 18) {
      FeatureLine(symbol: "wifi", title: String(localized: "Local, no cloud"), text: String(localized: "After setup DysonBar talks to the purifier directly over Wi-Fi. Nothing leaves your network."))
      FeatureLine(symbol: "chart.xyaxis.line", title: String(localized: "Air quality at a glance"), text: String(localized: "PM2.5, PM10, VOC, NO₂ and formaldehyde, with a 7-day history."))
      FeatureLine(symbol: "slider.horizontal.3", title: String(localized: "Full control"), text: String(localized: "Fan speed, auto mode, oscillation, night mode, timer, and heating or humidifying if your model has it."))

      Spacer(minLength: 12)

      Button {
        go(.signIn)
      } label: {
        Text("Get Started")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.extraLarge)
      .keyboardShortcut(.defaultAction)

      Text("DysonBar is an independent project and not affiliated with Dyson.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 48)
    .padding(.bottom, 28)
    .frame(maxHeight: .infinity)
  }

  private var done: some View {
    @Bindable var preferences = model.preferences
    return VStack(spacing: 16) {
      Form {
        Toggle(isOn: $preferences.launchAtLogin) {
          Text("Open at login")
          Text("So the air quality is always in the menu bar.")
        }
        Toggle(isOn: $preferences.notifyAirQuality) {
          Text("Notifications")
          Text("When the air gets bad, a filter runs out or the device reports a fault.")
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .scrollDisabled(true)
      .frame(height: 150)
      .toggleStyle(.switch)

      Spacer(minLength: 0)

      Button {
        if preferences.notifyAirQuality {
          preferences.notifyFilter = true
          preferences.notifyFaults = true
          model.notifier.requestPermission()
        } else {
          preferences.notifyFilter = false
          preferences.notifyFaults = false
        }
        preferences.hasCompletedOnboarding = true
        WindowPresenter.closeOnboarding()
      } label: {
        Text("Done")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.extraLarge)
      .keyboardShortcut(.defaultAction)
      .padding(.horizontal, 48)
      .padding(.bottom, 28)
    }
  }

  private func go(_ next: Step) {
    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) { step = next }
  }
}

private struct FeatureLine: View {
  let symbol: String
  let title: String
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .frame(width: 30)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.callout.weight(.semibold))
        Text(text)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}
