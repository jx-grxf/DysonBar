import Foundation
import Testing

@testable import DysonKit

@Suite struct SnapshotParsing {
  // Captured from a TP12 (type 438K) on 2026-10-25.
  static let currentState = """
    {"msg":"CURRENT-STATE","product-state":{"fpwr":"ON","auto":"ON","oson":"ON","nmod":"OFF","fnst":"FAN",\
    "wacd":"NONE","fnsp":"AUTO","cflr":"INV","hflr":"0034","sltm":"OFF","osal":"0097","osau":"0277","ancp":"CUST","fdir":"ON"}}
    """
  static let sensors = """
    {"msg":"ENVIRONMENTAL-CURRENT-SENSOR-DATA","data":{"tact":"2968","hact":"0052","pm25":"0002","pm10":"0001",\
    "va10":"0012","noxl":"0002","p25r":"0003","p10r":"0003","hcho":"0010","hchr":"0024","sltm":"OFF"}}
    """

  @Test func readsStateAndSensors() {
    var snapshot = DeviceSnapshot()
    #expect(snapshot.apply(Data(Self.currentState.utf8)) == .state)
    #expect(snapshot.apply(Data(Self.sensors.utf8)) == .sensors)

    #expect(snapshot.isOn && snapshot.isAuto && snapshot.isOscillating)
    #expect(snapshot.fanSpeed == nil)
    #expect(snapshot.oscillationWidth == 180)
    #expect(snapshot.hepaFilter == 34)
    #expect(snapshot.carbonFilter == nil)
    #expect(snapshot.sleepTimer == nil)
    #expect(snapshot.warningCode == nil)
    #expect(abs(snapshot.temperature! - 23.65) < 0.01)
    #expect(snapshot.humidity == 52)
    #expect(snapshot.value(for: .pm25) == 3)
    #expect(snapshot.value(for: .voc) == 1.2)
    #expect(snapshot.value(for: .hcho) == 0.024)
    #expect(snapshot.worstReading?.pollutant == .voc)
    #expect(snapshot.worstReading?.level == .good)
  }

  @Test func stateChangeTakesTheNewValue() {
    var snapshot = DeviceSnapshot()
    snapshot.apply(Data(Self.currentState.utf8))
    snapshot.apply(Data(#"{"msg":"STATE-CHANGE","product-state":{"fpwr":["ON","OFF"],"fnsp":["AUTO","0004"]}}"#.utf8))
    #expect(!snapshot.isOn)
    #expect(snapshot.fanSpeed == 4)
  }

  @Test func capabilitiesFollowReportedKeys() {
    var snapshot = DeviceSnapshot()
    snapshot.apply(Data(Self.currentState.utf8))
    let caps = snapshot.capabilities
    #expect(caps.contains([.auto, .oscillation, .oscillationAngles, .airflowDirection, .nightMode, .sleepTimer]))
    #expect(!caps.contains(.heating))
    #expect(!caps.contains(.humidifier))

    snapshot.apply(Data(#"{"msg":"STATE-CHANGE","product-state":{"hmod":["OFF","HEAT"],"hmax":["2930","2950"]}}"#.utf8))
    #expect(snapshot.capabilities.contains(.heating))
    #expect(snapshot.isHeating)
    #expect(snapshot.heatingTarget == 22)
  }

  @Test func faultsKeepOnlyActiveCodes() {
    var snapshot = DeviceSnapshot()
    snapshot.apply(Data(#"{"msg":"CURRENT-FAULTS","product-errors":{"amf1":"OK","sen1":"FAIL"},"product-warnings":{"fltr":"OK"}}"#.utf8))
    #expect(snapshot.faults == ["sen1": "FAIL"])
    snapshot.apply(Data(#"{"msg":"FAULTS-CHANGE","product-warnings":{"fltr":["OK","FAIL"]},"product-errors":{"sen1":["FAIL","OK"]}}"#.utf8))
    #expect(snapshot.faults == ["fltr": "FAIL"])
  }

  @Test func ignoresGarbage() {
    var snapshot = DeviceSnapshot()
    #expect(snapshot.apply(Data("not json".utf8)) == .none)
    #expect(snapshot.apply(Data(#"{"msg":"HELLO"}"#.utf8)) == .none)
    #expect(!snapshot.hasData)
  }
}

@Suite struct Commands {
  @Test func oscillationKeepsCentre() {
    let state = ["osal": "0097", "osau": "0277"]
    let command = DeviceCommand.oscillation(width: 90, current: state)
    #expect(command["osal"] == "0142")
    #expect(command["osau"] == "0232")
  }

  @Test func oscillationStaysInRange() {
    let command = DeviceCommand.oscillation(width: 350, current: ["osal": "0300", "osau": "0350"])
    #expect(command["osal"] == "0005")
    #expect(command["osau"] == "0355")
  }

  @Test func heatingTargetInTenthKelvin() {
    #expect(DeviceCommand.heatingTarget(celsius: 22)["hmax"] == "2952")
    #expect(DeviceCommand.heatingTarget(celsius: 50)["hmax"] == "3102")
  }

  @Test func speedIsClamped() {
    #expect(DeviceCommand.speed(14)["fnsp"] == "0010")
    #expect(DeviceCommand.speed(0)["fnsp"] == "0001")
  }
}

@Suite struct AirLevels {
  @Test func bandsMatchTheDevice() {
    #expect(Pollutant.pm25.level(for: 35) == .good)
    #expect(Pollutant.pm25.level(for: 36) == .fair)
    #expect(Pollutant.pm25.level(for: 999) == .severe)
    #expect(Pollutant.voc.level(for: 10.5) == .severe)
  }

  @Test func scoreIsContinuous() {
    #expect(Pollutant.pm25.score(for: 0) == 0)
    #expect(Pollutant.pm25.score(for: 35) == 1)
    #expect(abs(Pollutant.pm25.score(for: 44) - 1.5) < 0.001)
  }
}

@Suite struct MQTTFraming {
  @Test func remainingLengthRoundTrips() {
    for size in [0, 1, 127, 128, 16_383, 16_384, 70_000] {
      let packet = MQTTClient.packet(type: 0x30, body: Data(repeating: 7, count: size))
      let parsed = MQTTClient.nextPacket(in: packet)
      #expect(parsed?.body.count == size)
      #expect(parsed?.consumed == packet.count)
    }
  }

  @Test func waitsForIncompletePackets() {
    let packet = MQTTClient.packet(type: 0x30, body: Data(repeating: 1, count: 300))
    #expect(MQTTClient.nextPacket(in: packet.prefix(100)) == nil)
  }

  @Test func parsesQoS1Publish() {
    var body = MQTTClient.encode(string: "438K/SERIAL/status/current")
    body.append(contentsOf: [0x00, 0x2A])
    body.append(Data("{}".utf8))
    let publish = MQTTClient.parsePublish(header: 0x32, body: body)
    #expect(publish?.topic == "438K/SERIAL/status/current")
    #expect(publish?.packetID == Data([0x00, 0x2A]))
    #expect(publish?.payload == Data("{}".utf8))
  }

  @Test func rejectsTruncatedPublish() {
    #expect(MQTTClient.parsePublish(header: 0x32, body: Data([0x00, 0x09, 0x41])) == nil)
  }
}

@Suite struct Cloud {
  @Test func findsFirstObjectAfterPadding() {
    let data = Data(#"{"apPasswordHash":"abc}\"x","serial":"X"}{"second":1}"#.utf8) + Data([0x08, 0x08, 0x00])
    let object = DysonCloud.firstJSONObject(in: data)
    #expect(object?["apPasswordHash"] as? String == "abc}\"x")
  }

  @Test func decryptsLikeTheOfficialApp() throws {
    // Encrypted with the shared key and a zero IV, padded with backspaces.
    let plain = Data(#"{"serial":"AB1-EU-XYZ","apPasswordHash":"secret"}"#.utf8)
    let padded = plain + Data(repeating: 0x08, count: 16 - plain.count % 16)
    let encrypted = try Self.encrypt(padded)
    let object = try DysonCloud.decrypt(encrypted.base64EncodedString())
    #expect(object["apPasswordHash"] as? String == "secret")
  }

  @Test func skipsLegacyAndCloudOnlyDevices() {
    #expect(DysonCloud.device(from: ["serialNumber": "A", "type": "475"]) == nil)
    #expect(DysonCloud.device(from: ["serialNumber": "B", "type": "438K"]) == nil)
  }

  static func encrypt(_ data: Data) throws -> Data {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
    task.arguments = ["enc", "-aes-256-cbc", "-nopad", "-K", DysonCloud.key.map { String(format: "%02x", $0) }.joined(), "-iv", String(repeating: "0", count: 32)]
    let input = Pipe()
    let output = Pipe()
    task.standardInput = input
    task.standardOutput = output
    try task.run()
    input.fileHandleForWriting.write(data)
    try input.fileHandleForWriting.close()
    let result = output.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    return result
  }
}

@Suite struct HistoryLines {
  @Test func sampleRoundTrips() throws {
    let sample = Sample(date: Date(timeIntervalSince1970: 1_729_880_000), values: [.pm25: 3, .temperature: 23.6])
    let line = try #require(sample.line())
    #expect(Sample(line: line) == sample)
  }

  @MainActor @Test func storeKeepsOnePerMinuteAndPersists() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dysonbar-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date.now
    let store = HistoryStore(serial: "T", directory: directory)
    store.record(Sample(date: now, values: [.pm25: 1]))
    store.record(Sample(date: now.addingTimeInterval(30), values: [.pm25: 2]))
    store.record(Sample(date: now.addingTimeInterval(61), values: [.pm25: 3]))
    #expect(store.samples.map { $0.values[.pm25] } == [1, 3])

    try await Task.sleep(for: .milliseconds(200))
    let reloaded = HistoryStore(serial: "T", directory: directory)
    #expect(reloaded.samples.count == 2)
  }
}
