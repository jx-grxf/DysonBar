import Foundation
import Security

/// What DysonBar keeps about a device. The MQTT password lives in the Keychain,
/// everything else in `devices.json`.
public struct DeviceRecord: Codable, Identifiable, Hashable, Sendable {
  public var serial: String
  public var name: String?
  public var type: String
  public var model: String?
  public var variant: String?
  public var mqttRootTopic: String?
  /// Optional fixed address for networks where Bonjour does not reach the device.
  public var host: String?

  public init(
    serial: String, name: String?, type: String, model: String?, variant: String? = nil,
    mqttRootTopic: String?, host: String? = nil
  ) {
    self.serial = serial
    self.name = name
    self.type = type
    self.model = model
    self.variant = variant
    self.mqttRootTopic = mqttRootTopic
    self.host = host
  }

  public var id: String { serial }
  public var topicRoot: String { mqttRootTopic ?? type }
  public var displayName: String { name?.isEmpty == false ? name! : productName }
  public var productName: String { ProductCatalog.name(model: model, type: type) }
}

public enum DeviceStorage {
  public static let directory = FileManager.default.homeDirectoryForCurrentUser
    .appending(path: "Library/Application Support/DysonBar")
  static let file = directory.appending(path: "devices.json")

  public static func load() -> [DeviceRecord] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    return (try? JSONDecoder().decode([DeviceRecord].self, from: data)) ?? []
  }

  public static func save(_ records: [DeviceRecord]) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(records).write(to: file, options: .atomic)
  }
}

/// Generic passwords under the service name the old setup script used, so
/// existing installs keep working.
public enum DevicePasswords {
  static let service = "dyson-bar"

  public static func read(serial: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
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

  public static func save(_ password: String, serial: String) throws {
    let match: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: serial,
    ]
    let data = Data(password.utf8)
    var status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = match
      item[kSecValueData as String] = data
      item[kSecAttrLabel as String] = "Dyson \(serial)"
      status = SecItemAdd(item as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  public static func delete(serial: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: serial,
    ]
    SecItemDelete(query as CFDictionary)
  }
}
