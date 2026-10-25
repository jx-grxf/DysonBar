import DysonKit
import SwiftUI

/// The MyDyson sign-in: country and email, then the code Dyson mails and the
/// password. Used by onboarding and by "Add Device" in Settings.
struct SignInFlow: View {
  let onFinish: ([DysonCloud.Device]) -> Void

  @Environment(AppModel.self) private var model
  @AppStorage("signInCountry") private var country = Locale.current.region?.identifier ?? "DE"
  @AppStorage("signInEmail") private var email = ""
  @State private var code = ""
  @State private var password = ""
  @State private var challenge: DysonCloud.Challenge?
  @State private var isWorking = false
  @State private var error: String?
  @FocusState private var focus: Field?

  private enum Field { case email, code, password }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Form {
        if challenge == nil {
          Section {
            Picker("Country", selection: $country) {
              ForEach(Self.countries, id: \.code) { Text($0.name).tag($0.code) }
            }
            TextField("MyDyson email", text: $email, prompt: Text("name@example.com"))
              .textContentType(.username)
              .focused($focus, equals: .email)
              .onSubmit(requestCode)
          } footer: {
            Text("Use the account from the MyDyson app. Dyson emails you a one-time code.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        } else {
          Section {
            TextField("Code from the email", text: $code, prompt: Text("123456"))
              .textContentType(.oneTimeCode)
              .focused($focus, equals: .code)
            SecureField("MyDyson password", text: $password)
              .textContentType(.password)
              .focused($focus, equals: .password)
              .onSubmit(signIn)
          } header: {
            Text("Code sent to \(email)")
          } footer: {
            Text("DysonBar uses the password once to fetch the Wi-Fi key of each purifier. It doesn't store it.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }
      .formStyle(.grouped)
      .scrollContentBackground(.hidden)
      .scrollDisabled(true)
      .frame(height: challenge == nil ? 160 : 170)
      .disabled(isWorking)

      if let error {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .font(.callout)
          .foregroundStyle(Tokens.level(.poor))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 20)
          .transition(.opacity)
      }

      HStack {
        if challenge != nil {
          Button("Back") {
            withAnimation(Tokens.expandMotion) {
              challenge = nil
              error = nil
            }
          }
          .disabled(isWorking)
        }
        Spacer()
        if isWorking { ProgressView().controlSize(.small) }
        if challenge == nil {
          Button("Send Code", action: requestCode)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking || !email.contains("@"))
        } else {
          Button("Sign In", action: signIn)
            .keyboardShortcut(.defaultAction)
            .disabled(isWorking || code.count < 4 || password.isEmpty)
        }
      }
      .controlSize(.large)
      .padding(.horizontal, 20)
    }
    .animation(Tokens.expandMotion, value: challenge == nil)
    .animation(Tokens.expandMotion, value: error)
    .onAppear { focus = email.isEmpty ? .email : nil }
  }

  private func requestCode() {
    guard email.contains("@"), !isWorking else { return }
    email = email.trimmingCharacters(in: .whitespaces)
    run {
      let challenge = try await DysonCloud(countryCode: country).requestCode(email: email)
      self.challenge = challenge
      focus = .code
    }
  }

  private func signIn() {
    guard let challenge, !isWorking else { return }
    run {
      let devices = try await DysonCloud(countryCode: country)
        .fetchDevices(challenge: challenge, code: code, password: password)
      password = ""
      try model.store.add(devices)
      onFinish(devices)
    }
  }

  private func run(_ work: @escaping @MainActor () async throws -> Void) {
    isWorking = true
    error = nil
    Task {
      do {
        try await work()
      } catch let failure as URLError {
        error = failure.code == .notConnectedToInternet
          ? String(localized: "This Mac is offline. Signing in needs the internet once.")
          : failure.localizedDescription
      } catch {
        self.error = error.localizedDescription
      }
      isWorking = false
    }
  }

  private static let countries: [(code: String, name: String)] = Locale.Region.isoRegions
    .filter { $0.identifier.count == 2 && Int($0.identifier) == nil }
    .compactMap { region in
      Locale.current.localizedString(forRegionCode: region.identifier).map { (region.identifier, $0) }
    }
    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
}
