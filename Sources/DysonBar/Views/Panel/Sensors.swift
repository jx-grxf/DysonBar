import Charts
import DysonKit
import SwiftUI

/// One column per pollutant: level dot, value, and the last six hours as a
/// sparkline. A click opens the full history below.
struct SensorRow: View {
  let device: DysonDevice
  @Binding var selection: Metric?

  @Namespace private var highlight

  var body: some View {
    let readings = device.snapshot.readings
    let recent = recentSamples
    HStack(spacing: 4) {
      ForEach(readings) { reading in
        let metric = Metric(reading.pollutant)
        Button {
          selection = selection == metric ? nil : metric
        } label: {
          SensorColumn(
            reading: reading,
            values: recent.compactMap { $0.values[metric] },
            isSelected: selection == metric
          )
          .background {
            if selection == metric {
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Tokens.cardFill)
                .matchedGeometryEffect(id: "selection", in: highlight)
            }
          }
        }
        .buttonStyle(.plain)
        .help("\(reading.pollutant.longTitle): \(reading.pollutant.format(reading.value)) \(reading.pollutant.unit), \(reading.level.title)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.pollutant.longTitle)
        .accessibilityValue("\(reading.pollutant.format(reading.value)) \(reading.pollutant.unit), \(reading.level.title)")
        .accessibilityHint(String(localized: "Shows the history"))
        .accessibilityAddTraits(selection == metric ? [.isButton, .isSelected] : .isButton)
      }
    }
    .animation(Tokens.expandMotion, value: selection)
  }

  private var recentSamples: [Sample] {
    _ = device.historyRevision
    return device.history.samples(since: .now.addingTimeInterval(-6 * 3600))
  }
}

private struct SensorColumn: View {
  let reading: Reading
  let values: [Double]
  let isSelected: Bool
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 5) {
        Circle()
          .fill(reading.level.color)
          .frame(width: 6, height: 6)
        Text(reading.pollutant.title)
          .font(.caption2.weight(.medium))
          .foregroundStyle(.secondary)
      }
      Text(reading.pollutant.format(reading.value))
        .font(.system(.callout, design: .rounded, weight: .semibold).monospacedDigit())
        .contentTransition(.numericText(value: reading.value))
      if values.count > 1 {
        Sparkline(values: values, tint: reading.level.color)
          .frame(height: 16)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      hovering && !isSelected ? Tokens.hover : .clear,
      in: .rect(cornerRadius: 10, style: .continuous)
    )
    .contentShape(.rect)
    .onHover { hovering = $0 }
    .animation(Tokens.hoverMotion, value: hovering)
    .animation(Tokens.dataMotion, value: reading.value)
  }
}

struct Sparkline: View {
  let values: [Double]
  let tint: Color

  var body: some View {
    Canvas { context, size in
      let points = Self.downsample(values, to: 48)
      guard points.count > 1, let low = points.min(), let high = points.max() else {
        var flat = Path()
        flat.move(to: CGPoint(x: 0, y: size.height - 1))
        flat.addLine(to: CGPoint(x: size.width, y: size.height - 1))
        context.stroke(flat, with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [2, 3]))
        return
      }
      // A flat line on a near-constant signal reads better than noise blown up to full height.
      let span = max(high - low, abs(high) * 0.15, 0.001)
      let step = size.width / CGFloat(points.count - 1)
      var line = Path()
      for (index, value) in points.enumerated() {
        let point = CGPoint(
          x: CGFloat(index) * step,
          y: size.height - 1.5 - CGFloat((value - low) / span) * (size.height - 3))
        index == 0 ? line.move(to: point) : line.addLine(to: point)
      }
      var area = line
      area.addLine(to: CGPoint(x: size.width, y: size.height))
      area.addLine(to: CGPoint(x: 0, y: size.height))
      area.closeSubpath()
      context.fill(
        area,
        with: .linearGradient(
          Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
      context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
    .accessibilityHidden(true)
  }

  static func downsample(_ values: [Double], to count: Int) -> [Double] {
    guard values.count > count else { return values }
    let bucket = Double(values.count) / Double(count)
    return (0..<count).map { index in
      let slice = values[Int(Double(index) * bucket)..<min(Int(Double(index + 1) * bucket), values.count)]
      return slice.reduce(0, +) / Double(max(slice.count, 1))
    }
  }
}

// MARK: - History

enum HistoryRange: String, CaseIterable, Identifiable {
  case day, week

  var id: String { rawValue }
  var title: String {
    switch self {
    case .day: String(localized: "24 hours")
    case .week: String(localized: "7 days")
    }
  }
  var interval: TimeInterval { self == .day ? 24 * 3600 : 7 * 24 * 3600 }
  /// Minutes per plotted point: the chart stays under ~300 marks either way.
  var bucket: TimeInterval { self == .day ? 5 * 60 : 30 * 60 }
}

struct HistoryCard: View {
  let device: DysonDevice
  let metric: Metric
  let onClose: () -> Void

  @AppStorage("historyRange") private var range: HistoryRange = .day
  @State private var hovered: Date?

  var body: some View {
    let points = self.points
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 1) {
          Text(metric.longTitle)
            .font(.callout.weight(.semibold))
          Text(summary(points))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .contentTransition(.numericText())
        }
        Spacer()
        Picker("Range", selection: $range) {
          ForEach(HistoryRange.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Button(action: onClose) {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .bold))
            .frame(width: 20, height: 20)
            .background(Tokens.hover, in: .circle)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Close"))
        .accessibilityLabel(String(localized: "Close history"))
      }

      if points.count < 2 {
        Text("DysonBar records a value every minute. The chart fills up while the app runs.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 110)
          .multilineTextAlignment(.center)
      } else {
        chart(points)
          .frame(height: 120)
      }
    }
    .padding(12)
    .background(Tokens.cardFill, in: .rect(cornerRadius: Tokens.cardRadius, style: .continuous))
  }

  private func chart(_ points: [ChartPoint]) -> some View {
    Chart {
      ForEach(points) { point in
        AreaMark(x: .value("Time", point.date), y: .value(metric.title, point.value))
          .interpolationMethod(.monotone)
          .foregroundStyle(
            LinearGradient(colors: [tint.opacity(0.3), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
        LineMark(x: .value("Time", point.date), y: .value(metric.title, point.value))
          .interpolationMethod(.monotone)
          .foregroundStyle(tint)
          .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
      }
      if let hovered, let point = points.min(by: { abs($0.date.timeIntervalSince(hovered)) < abs($1.date.timeIntervalSince(hovered)) }) {
        RuleMark(x: .value("Time", point.date))
          .foregroundStyle(.secondary.opacity(0.4))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        PointMark(x: .value("Time", point.date), y: .value(metric.title, point.value))
          .foregroundStyle(tint)
          .symbolSize(40)
          .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit, y: .disabled)) {
            VStack(spacing: 0) {
              Text(metric.format(point.value))
                .font(.caption.weight(.semibold).monospacedDigit())
              Text(point.date, format: range == .day ? .dateTime.hour().minute() : .dateTime.weekday().hour())
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: .rect(cornerRadius: 6, style: .continuous))
          }
      }
    }
    .chartXSelection(value: $hovered)
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: range == .day ? 6 : 7)) { _ in
        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
        AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.weekday(.abbreviated))
      }
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
        AxisGridLine().foregroundStyle(.primary.opacity(0.06))
        AxisValueLabel()
      }
    }
    .chartYScale(domain: .automatic(includesZero: metric.includesZero))
  }

  private var tint: Color {
    if let pollutant = metric.pollutant, let value = device.snapshot.value(for: pollutant) {
      return pollutant.level(for: value).color
    }
    return metric == .temperature ? Tokens.heat : Tokens.water
  }

  private func summary(_ points: [ChartPoint]) -> String {
    guard let low = points.map(\.value).min(), let high = points.map(\.value).max() else {
      return String(localized: "No data yet")
    }
    let unit = metric.unit
    return String(localized: "Min \(metric.format(low)) · Max \(metric.format(high)) \(unit)")
  }

  private struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
  }

  /// Averages into fixed buckets so a week of minute samples stays smooth and fast.
  private var points: [ChartPoint] {
    _ = device.historyRevision
    let samples = device.history.samples(since: .now.addingTimeInterval(-range.interval))
    var buckets: [Int: (sum: Double, count: Int)] = [:]
    for sample in samples {
      guard let value = sample.values[metric] else { continue }
      let key = Int(sample.date.timeIntervalSince1970 / range.bucket)
      buckets[key, default: (0, 0)].sum += value
      buckets[key, default: (0, 0)].count += 1
    }
    return buckets.keys.sorted().map { key in
      let bucket = buckets[key]!
      return ChartPoint(
        date: Date(timeIntervalSince1970: (Double(key) + 0.5) * range.bucket),
        value: bucket.sum / Double(bucket.count))
    }
  }
}

extension Metric {
  var pollutant: Pollutant? { Pollutant(rawValue: rawValue) }

  var title: String {
    switch self {
    case .temperature: String(localized: "Temperature")
    case .humidity: String(localized: "Humidity")
    default: pollutant!.title
    }
  }

  var longTitle: String {
    switch self {
    case .temperature: String(localized: "Temperature")
    case .humidity: String(localized: "Humidity")
    default: pollutant!.longTitle
    }
  }

  var unit: String {
    switch self {
    case .temperature: "°C"
    case .humidity: "%"
    default: pollutant!.unit
    }
  }

  var includesZero: Bool { pollutant != nil }

  func format(_ value: Double) -> String {
    switch self {
    case .temperature: value.formatted(.number.precision(.fractionLength(1)))
    case .humidity: value.formatted(.number.precision(.fractionLength(0)))
    default: pollutant!.format(value)
    }
  }
}
