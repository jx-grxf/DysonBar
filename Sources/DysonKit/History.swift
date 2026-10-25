import Foundation

public enum Metric: String, CaseIterable, Codable, Sendable {
  case pm25, pm10, voc, no2, hcho, temperature, humidity

  public init(_ pollutant: Pollutant) {
    self = Metric(rawValue: pollutant.rawValue)!
  }
}

public struct Sample: Codable, Equatable, Sendable {
  public let date: Date
  public let values: [Metric: Double]

  public init(date: Date, values: [Metric: Double]) {
    self.date = date
    self.values = values
  }

  public init(snapshot: DeviceSnapshot, date: Date) {
    var values: [Metric: Double] = [:]
    for reading in snapshot.readings { values[Metric(reading.pollutant)] = reading.value }
    values[.temperature] = snapshot.temperature
    values[.humidity] = snapshot.humidity.map(Double.init)
    self.init(date: date, values: values)
  }

  // One short line per minute: {"t":1729880000,"pm25":3,...}
  private struct Line: Codable {
    let t: Int
    let v: [String: Double]
  }

  func line() -> Data? {
    let line = Line(
      t: Int(date.timeIntervalSince1970),
      v: Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) }))
    return try? JSONEncoder().encode(line)
  }

  init?(line: Data) {
    guard let decoded = try? JSONDecoder().decode(Line.self, from: line) else { return nil }
    date = Date(timeIntervalSince1970: TimeInterval(decoded.t))
    values = Dictionary(uniqueKeysWithValues: decoded.v.compactMap { key, value in
      Metric(rawValue: key).map { ($0, value) }
    })
  }
}

/// Seven days of one-minute samples per device in a JSON Lines file. About
/// 10,000 lines, so it loads in milliseconds and needs no database.
@MainActor
public final class HistoryStore {
  public static let retention: TimeInterval = 7 * 24 * 3600
  static let spacing: TimeInterval = 60

  public private(set) var samples: [Sample] = []
  private let file: URL
  private let writer = DispatchQueue(label: "DysonBar.history", qos: .utility)

  public init(serial: String, directory: URL = DeviceStorage.directory.appending(path: "History")) {
    file = directory.appending(path: "\(serial).jsonl")
    samples = Self.read(file)
    prune(now: .now, rewrite: true)
  }

  /// Keeps at most one sample a minute; the device sends sensor data every 30 s.
  public func record(_ sample: Sample) {
    guard !sample.values.isEmpty else { return }
    if let last = samples.last, sample.date.timeIntervalSince(last.date) < Self.spacing { return }
    samples.append(sample)
    guard let line = sample.line() else { return }
    let file = file
    writer.async {
      try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      if let handle = try? FileHandle(forWritingTo: file) {
        handle.seekToEndOfFile()
        handle.write(line + Data([0x0A]))
        try? handle.close()
      } else {
        try? (line + Data([0x0A])).write(to: file)
      }
    }
    if let first = samples.first, sample.date.timeIntervalSince(first.date) > Self.retention + 3600 {
      prune(now: sample.date, rewrite: true)
    }
  }

  public func samples(since date: Date) -> [Sample] {
    let start = samples.firstIndex { $0.date >= date } ?? samples.endIndex
    return Array(samples[start...])
  }

  public func delete() {
    samples = []
    let file = file
    writer.async { try? FileManager.default.removeItem(at: file) }
  }

  private func prune(now: Date, rewrite: Bool) {
    let cutoff = now.addingTimeInterval(-Self.retention)
    guard let first = samples.first, first.date < cutoff else { return }
    samples.removeAll { $0.date < cutoff }
    guard rewrite else { return }
    let data = samples.compactMap { $0.line() }.reduce(into: Data()) { $0 += $1 + Data([0x0A]) }
    let file = file
    writer.async { try? data.write(to: file, options: .atomic) }
  }

  nonisolated static func read(_ file: URL) -> [Sample] {
    guard let data = try? Data(contentsOf: file) else { return [] }
    return data.split(separator: 0x0A).compactMap { Sample(line: Data($0)) }.sorted { $0.date < $1.date }
  }
}
