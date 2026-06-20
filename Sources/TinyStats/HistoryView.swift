import SwiftUI
import Charts
import TinyStatsCore

struct HistoryView: View {
    let samples: [MetricSample]
    let order: [OverviewSection]
    let snapshot: MetricsSnapshot

    var body: some View {
        if samples.count < 2 {
            VStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line").foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(Loc.t(.collectingHistory))
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 320, alignment: .center)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Text(Loc.t(.lastSpan, spanLabel))
                        .font(.system(.caption2))
                        .foregroundStyle(.tertiary)
                }
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(order) { section in
                        if shouldShow(section) {
                            chartBlock(section)
                        }
                    }
                }
                .padding(.bottom, 6)   // keep the last chart's axis labels from being clipped
            }
        }
    }

    private func shouldShow(_ section: OverviewSection) -> Bool {
        if section == .battery { return snapshot.battery != nil }
        return true
    }

    /// Exact x-domain so charts fill the full width (Swift Charts otherwise pads the
    /// quantitative axis toward "nice" bounds, pushing data to the right).
    private var idDomain: ClosedRange<Int> {
        let lo = samples.first?.id ?? 0
        let hi = samples.last?.id ?? lo
        return lo...max(hi, lo + 1)
    }

    /// Human label for the time window the charts currently cover.
    private var spanLabel: String {
        guard let first = samples.first?.time, let last = samples.last?.time else { return "—" }
        let seconds = Int(last.timeIntervalSince(first).rounded())
        if seconds < 90 { return "\(max(1, seconds))s" }
        return Format.duration(minutes: (seconds + 30) / 60)
    }

    // MARK: Chart blocks

    @ViewBuilder
    private func chartBlock(_ section: OverviewSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch section {
            case .network:
                networkHeader
                NetworkChart(samples: samples, domain: idDomain).frame(height: 80)
            case .disk:
                diskHeader
                DiskChart(samples: samples, domain: idDomain).frame(height: 80)
            case .battery:
                SectionHeaderRow(symbol: section.symbol, title: section.label,
                                 value: currentValue(section),
                                 tint: currentLowPower ? .yellow : section.tint)
                batteryChart.frame(height: 64)
            default:
                standardHeader(section)
                simpleChart(section).frame(height: 64)
            }
        }
    }

    // MARK: Headers

    private func standardHeader(_ section: OverviewSection) -> some View {
        SectionHeaderRow(symbol: section.symbol, title: section.label,
                         value: currentValue(section), tint: section.tint)
    }

    private var networkHeader: some View {
        SectionHeaderRow(symbol: "network", title: Loc.t(.network)) {
            HStack(spacing: 8) {
                rateChip("DL", snapshot.network.downloadBytesPerSec, Palette.ingress)
                rateChip("UL", snapshot.network.uploadBytesPerSec, Palette.egress)
            }
        }
    }

    private var diskHeader: some View {
        SectionHeaderRow(symbol: "internaldrive", title: Loc.t(.disk)) {
            HStack(spacing: 8) {
                rateChip(Loc.t(.read), snapshot.disk.readBytesPerSec, Palette.egress)
                rateChip(Loc.t(.write), snapshot.disk.writeBytesPerSec, Palette.ingress)
            }
        }
    }

    /// A small "DL 1.2 MB/s" chip. The teal "up" series and orange "down" series
    /// match the bidirectional charts below, so colour identifies direction.
    private func rateChip(_ tag: String, _ bytesPerSec: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(tag).font(.system(.caption2, weight: .semibold))
            Text(Format.rate(bytesPerSec))
                .font(.system(.subheadline).monospacedDigit())
        }
        .foregroundStyle(Format.isZeroRate(bytesPerSec) ? AnyShapeStyle(.tertiary) : AnyShapeStyle(color))
    }

    // MARK: Simple 0–1 chart

    @ViewBuilder
    private func simpleChart(_ section: OverviewSection) -> some View {
        Chart(samples) { sample in
            AreaMark(x: .value("t", sample.id), y: .value("v", sampleValue(sample, section)))
                .foregroundStyle(section.tint.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", sample.id), y: .value("v", sampleValue(sample, section)))
                .foregroundStyle(section.tint)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: idDomain)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text("\(Int(v * 100))%").font(.system(size: 8))
                    }
                }
            }
        }
    }

    // MARK: Battery chart (the line is yellow while Low Power Mode was on, green otherwise)

    /// Current Low Power state (the most recent sample), for the live header value tint.
    private var currentLowPower: Bool { samples.last?.lowPower ?? false }

    /// A left-to-right gradient that paints each Low Power span yellow and the rest green, with
    /// *hard* stops (two stops at one location) at every transition midpoint. Applied to one
    /// continuous line and one continuous area, so the whole metric is a single mark — no extra
    /// series to stack into spikes, and no gaps. The data is continuous; only the colour changes.
    private func batteryGradient(opacity: Double) -> LinearGradient {
        func color(_ s: MetricSample) -> Color { (s.lowPower ? .yellow : Palette.battery).opacity(opacity) }
        guard let first = samples.first, let last = samples.last else {
            return LinearGradient(colors: [Palette.battery.opacity(opacity)],
                                  startPoint: .leading, endPoint: .trailing)
        }
        let lo = Double(first.id), span = max(Double(last.id) - lo, 1)
        var stops: [Gradient.Stop] = [.init(color: color(first), location: 0)]
        for k in 1..<samples.count where samples[k].lowPower != samples[k - 1].lowPower {
            let loc = ((Double(samples[k - 1].id) + Double(samples[k].id)) / 2 - lo) / span
            stops.append(.init(color: color(samples[k - 1]), location: loc))
            stops.append(.init(color: color(samples[k]), location: loc))
        }
        stops.append(.init(color: color(last), location: 1))
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder
    private var batteryChart: some View {
        Chart {
            ForEach(samples) { s in
                AreaMark(x: .value("t", s.id), y: .value("v", s.battery))
                    .interpolationMethod(.monotone)
            }
            .foregroundStyle(batteryGradient(opacity: 0.15))
            ForEach(samples) { s in
                LineMark(x: .value("t", s.id), y: .value("v", s.battery))
                    .interpolationMethod(.monotone)
            }
            .foregroundStyle(batteryGradient(opacity: 1))
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: idDomain)
        .chartYScale(domain: 0...1)
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 0.5, 1]) { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text("\(Int(v * 100))%").font(.system(size: 8))
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func sampleValue(_ sample: MetricSample, _ section: OverviewSection) -> Double {
        switch section {
        case .cpu:     return sample.cpu
        case .gpu:     return sample.gpu
        case .memory:  return sample.memory
        case .battery: return sample.battery
        case .network, .disk: return 0
        }
    }

    private func currentValue(_ section: OverviewSection) -> String {
        switch section {
        case .cpu:     return Format.percent(snapshot.cpu.total)
        case .gpu:     return Format.percent(snapshot.gpu.utilization)
        case .memory:  return Format.percent(snapshot.memory.fraction)
        case .battery: return Format.percent(snapshot.battery?.charge ?? 0)
        case .network, .disk: return ""
        }
    }
}

// MARK: - Network chart (download up / upload down)

private struct NetworkChart: View {
    let samples: [MetricSample]
    let domain: ClosedRange<Int>

    private var peak: Double {
        max(samples.map(\.netDown).max() ?? 0, samples.map(\.netUp).max() ?? 0, 1024)
    }
    private var useMB: Bool { peak > 2_097_152 }
    private var div: Double { useMB ? 1_048_576 : 1_024 }
    private var unit: String { useMB ? "MB/s" : "KB/s" }

    var body: some View {
        Chart(samples) { s in
            // Upload above zero (orange), download below zero (teal).
            AreaMark(x: .value("t", s.id), y: .value("v", s.netUp / div),
                     series: .value("s", "↑"))
                .foregroundStyle(Palette.egress.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", s.id), y: .value("v", s.netUp / div),
                     series: .value("s", "↑"))
                .foregroundStyle(Palette.egress)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("t", s.id), y: .value("v", -(s.netDown / div)),
                     series: .value("s", "↓"))
                .foregroundStyle(Palette.ingress.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", s.id), y: .value("v", -(s.netDown / div)),
                     series: .value("s", "↓"))
                .foregroundStyle(Palette.ingress)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text(self.axisLabel(Swift.abs(v))).font(.system(size: 8))
                    }
                }
            }
        }
    }

    private func axisLabel(_ absV: Double) -> String {
        if absV < 0.01 { return "0" }
        if absV < 10 { return String(format: "%.1f \(unit)", absV) }
        return String(format: "%.0f \(unit)", absV)
    }
}

// MARK: - Disk chart (read up / write down)

private struct DiskChart: View {
    let samples: [MetricSample]
    let domain: ClosedRange<Int>

    private var peak: Double {
        max(samples.map(\.diskRead).max() ?? 0, samples.map(\.diskWrite).max() ?? 0, 1024)
    }
    private var useMB: Bool { peak > 2_097_152 }
    private var div: Double { useMB ? 1_048_576 : 1_024 }
    private var unit: String { useMB ? "MB/s" : "KB/s" }

    var body: some View {
        Chart(samples) { s in
            AreaMark(x: .value("t", s.id), y: .value("v", s.diskRead / div),
                     series: .value("s", "R"))
                .foregroundStyle(Palette.egress.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", s.id), y: .value("v", s.diskRead / div),
                     series: .value("s", "R"))
                .foregroundStyle(Palette.egress)
                .interpolationMethod(.monotone)
            AreaMark(x: .value("t", s.id), y: .value("v", -(s.diskWrite / div)),
                     series: .value("s", "W"))
                .foregroundStyle(Palette.ingress.opacity(0.15))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", s.id), y: .value("v", -(s.diskWrite / div)),
                     series: .value("s", "W"))
                .foregroundStyle(Palette.ingress)
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { mark in
                AxisGridLine()
                AxisValueLabel {
                    if let v = mark.as(Double.self) {
                        Text(self.axisLabel(Swift.abs(v))).font(.system(size: 8))
                    }
                }
            }
        }
    }

    private func axisLabel(_ absV: Double) -> String {
        if absV < 0.01 { return "0" }
        if absV < 10 { return String(format: "%.1f \(unit)", absV) }
        return String(format: "%.0f \(unit)", absV)
    }
}
