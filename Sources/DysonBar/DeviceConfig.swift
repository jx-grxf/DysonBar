import Foundation
import Security

/// Written by `tools/fetch-credentials.py`; the MQTT password lives in the Keychain.
struct DeviceConfig: Decodable {
  let serial: String
  let name: String?
  let type: String
  let model: String?
  let mqttRootTopic: String?
  /// Optional fixed address for networks where Bonjour does not reach the device.
  let host: String?

  var topicRoot: String { mqttRootTopic ?? type }

  var productName: String {
    switch model {
    case "TP12": "PC2 De-NOx"
    case "TP11": "PC1"
    case "TP09": "TP09 Formaldehyde"
    case "TP07": "TP07"
    case let model?: model
    case nil: "Dyson"
    }
  }

  static let directory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/DysonBar")

  enum LoadError: LocalizedError {
    case noConfig
    case noPassword(String)

    var errorDescription: String? {
      switch self {
      case .noConfig:
        "Noch kein Gerät eingerichtet. Führ einmal tools/fetch-credentials.py aus."
      case .noPassword(let serial):
        "Kein Passwort für \(serial) im Schlüsselbund."
      }
    }
  }

  static func loadFirst() throws -> (DeviceConfig, String) {
    let url = directory.appending(path: "devices.json")
    guard let data = try? Data(contentsOf: url),
      let config = try JSONDecoder().decode([DeviceConfig].self, from: data).first
    else { throw LoadError.noConfig }
    guard let password = keychainPassword(serial: config.serial) else {
      throw LoadError.noPassword(config.serial)
    }
    return (config, password)
  }

  private static func keychainPassword(serial: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "dyson-bar",
      kSecAttrAccount as String: serial,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
