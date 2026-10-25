import CommonCrypto
import Foundation

/// The MyDyson login, used once per account to fetch each device's local MQTT
/// password. Nothing from here is stored except that password and the device
/// list; the account token is dropped when the flow ends.
public struct DysonCloud: Sendable {
  public struct Challenge: Sendable {
    public let id: String
    public let email: String
  }

  public struct Device: Sendable {
    public let record: DeviceRecord
    public let password: String
  }

  public enum Failure: LocalizedError, Equatable {
    case invalidEmail
    case wrongCodeOrPassword
    case rateLimited
    case server(Int)
    case unreadableResponse
    case noLocalDevices

    public var errorDescription: String? {
      switch self {
      case .invalidEmail:
        String(localized: "Dyson couldn't send a code to this address. Check the email and the country.")
      case .wrongCodeOrPassword:
        String(localized: "The code or the password is wrong.")
      case .rateLimited:
        String(localized: "Too many attempts. Wait a few minutes and try again.")
      case .server(let status):
        String(localized: "Dyson's server answered with error \(status).")
      case .unreadableResponse:
        String(localized: "Dyson's server sent something DysonBar can't read.")
      case .noLocalDevices:
        String(localized: "This account has no device that can be controlled over Wi-Fi.")
      }
    }
  }

  public let countryCode: String
  private let session: URLSession

  public init(countryCode: String, session: URLSession = .shared) {
    self.countryCode = countryCode.uppercased()
    self.session = session
  }

  /// Mainland China accounts live on a separate host.
  var host: String { countryCode == "CN" ? "https://appapi.cp.dyson.cn" : "https://appapi.cp.dyson.com" }

  public func requestCode(email: String) async throws -> Challenge {
    _ = try? await call("GET", "/v1/provisioningservice/application/Android/version", query: false)
    let body = try await call("POST", "/v3/userregistration/email/auth", json: ["email": email])
    guard let id = body["challengeId"] as? String else { throw Failure.unreadableResponse }
    return Challenge(id: id, email: email)
  }

  public func fetchDevices(challenge: Challenge, code: String, password: String) async throws -> [Device] {
    let login = try await call(
      "POST", "/v3/userregistration/email/verify",
      json: [
        "challengeId": challenge.id,
        "email": challenge.email,
        "otpCode": code.trimmingCharacters(in: .whitespaces),
        "password": password,
      ])
    guard let token = login["token"] as? String else { throw Failure.unreadableResponse }
    let manifest = try await callList("GET", "/v3/manifest", token: token)
    let devices = manifest.compactMap(Self.device(from:))
    guard !devices.isEmpty else { throw Failure.noLocalDevices }
    return devices
  }

  static func device(from entry: [String: Any]) -> Device? {
    guard let serial = entry["serialNumber"] as? String,
      let type = entry["type"] as? String,
      ProductCatalog.isSupported(type: type),
      let mqtt = (entry["connectedConfiguration"] as? [String: Any])?["mqtt"] as? [String: Any],
      let encrypted = mqtt["localBrokerCredentials"] as? String,
      let credentials = try? decrypt(encrypted),
      let password = credentials["apPasswordHash"] as? String
    else { return nil }
    let record = DeviceRecord(
      serial: serial,
      name: entry["name"] as? String,
      type: type,
      model: entry["model"] as? String,
      variant: entry["variant"] as? String,
      mqttRootTopic: mqtt["mqttRootTopicLevel"] as? String
    )
    return Device(record: record, password: password)
  }

  // MARK: Credentials

  /// The key every Dyson client uses; it ships in the Android app.
  static let key = Data((1...32).map(UInt8.init))

  static func decrypt(_ base64: String) throws -> [String: Any] {
    guard let input = Data(base64Encoded: base64), input.count % kCCBlockSizeAES128 == 0 else {
      throw Failure.unreadableResponse
    }
    var output = Data(count: input.count)
    var written = 0
    let iv = Data(count: kCCBlockSizeAES128)
    let status = output.withUnsafeMutableBytes { out in
      input.withUnsafeBytes { inBytes in
        key.withUnsafeBytes { keyBytes in
          iv.withUnsafeBytes { ivBytes in
            CCCrypt(
              CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), 0,
              keyBytes.baseAddress, key.count, ivBytes.baseAddress,
              inBytes.baseAddress, input.count, out.baseAddress, input.count, &written)
          }
        }
      }
    }
    guard status == kCCSuccess else { throw Failure.unreadableResponse }
    // No PKCS7: the plaintext is padded with backspaces or NULs, and some
    // devices append a second JSON object after the first.
    guard let object = firstJSONObject(in: output.prefix(written)) else { throw Failure.unreadableResponse }
    return object
  }

  static func firstJSONObject(in data: Data) -> [String: Any]? {
    var depth = 0
    var inString = false
    var escaped = false
    for (offset, byte) in data.enumerated() {
      if inString {
        if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
        continue
      }
      switch byte {
      case UInt8(ascii: "\""): inString = true
      case UInt8(ascii: "{"): depth += 1
      case UInt8(ascii: "}"):
        depth -= 1
        if depth == 0 {
          let slice = data.prefix(offset + 1)
          return try? JSONSerialization.jsonObject(with: slice) as? [String: Any]
        }
      default: break
      }
    }
    return nil
  }

  // MARK: HTTP

  private func request(_ method: String, _ path: String, json: [String: String]?, token: String?, query: Bool) throws -> URLRequest {
    var components = URLComponents(string: host + path)!
    if query {
      let language = Locale.current.language.languageCode?.identifier ?? "en"
      components.queryItems = [
        URLQueryItem(name: "country", value: countryCode),
        URLQueryItem(name: "culture", value: "\(language)-\(countryCode)"),
      ]
    }
    var request = URLRequest(url: components.url!, timeoutInterval: 20)
    request.httpMethod = method
    // The API rejects requests that don't look like the Android app.
    request.setValue("android client", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let json { request.httpBody = try JSONSerialization.data(withJSONObject: json) }
    return request
  }

  private func send(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200..<300: return data
    case 400..<429 where request.url?.path.hasSuffix("/auth") == true: throw Failure.invalidEmail
    case 400, 401, 403: throw Failure.wrongCodeOrPassword
    case 429: throw Failure.rateLimited
    default: throw Failure.server(status)
    }
  }

  private func call(
    _ method: String, _ path: String, json: [String: String]? = nil, token: String? = nil, query: Bool = true
  ) async throws -> [String: Any] {
    let data = try await send(request(method, path, json: json, token: token, query: query))
    if data.isEmpty { return [:] }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw Failure.unreadableResponse
    }
    return object
  }

  private func callList(_ method: String, _ path: String, token: String) async throws -> [[String: Any]] {
    let data = try await send(request(method, path, json: nil, token: token, query: false))
    guard let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw Failure.unreadableResponse
    }
    return list
  }
}
