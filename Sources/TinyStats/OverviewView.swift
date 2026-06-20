import SwiftUI
import TinyStatsCore

struct OverviewView: View {
    let snapshot: MetricsSnapshot
    let topCount: Int
    let order: [OverviewSection]
    var processListEnabled: Bool = true
    var showProcessesCPU: Bool = true
    var showProcessesMemory: Bool = true
    var showProcessesDisk: Bool = true
    var nerd: Bool = false
    var lowPower: Bool = false

    private var cpuProcesses: Bool { processListEnabled && showProcessesCPU }
    private var memoryProcesses: Bool { processListEnabled && showProcessesMemory }
    private var diskProcesses: Bool { processListEnabled && showProcessesDisk }

    private var visibleOrder: [OverviewSection] {
        order.filter { $0 != .battery || snapshot.battery != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(visibleOrder.enumerated()), id: \.element) { index, section in
                if index > 0 {
                    Divider().opacity(0.4)   // subtle delineation between sections
                }
                sectionView(section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: OverviewSection) -> some View {
        switch section {
        case .cpu:      cpuSection
        case .memory:   memorySection
        case .network:  networkSection
        case .disk:     diskSection
        case .gpu:      gpuSection
        case .battery:
            if let battery = snapshot.battery { batterySection(battery) }
        }
    }

    // MARK: CPU

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderRow(symbol: "cpu", title: Loc.t(.cpu),
                             value: Format.percent(snapshot.cpu.total), tint: Palette.cpu)
            CoreBarsView(perCore: snapshot.cpu.perCore)
            if cpuProcesses {
                processList(snapshot.processes.sorted { $0.cpu > $1.cpu }) { p in
                    Format.percent(p.cpu)
                }
            }
        }
    }

    // MARK: GPU

    private var gpuSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderRow(symbol: "cpu.fill", title: Loc.t(.gpu),
                             value: Format.percent(snapshot.gpu.utilization), tint: Palette.gpu)
            ProgressBar(fraction: snapshot.gpu.utilization, tint: Palette.gpu)
        }
    }

    // MARK: Memory

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderRow(symbol: "memorychip", title: Loc.t(.memory),
                             value: Format.percent(snapshot.memory.fraction), tint: Palette.memory)
            detailBar(
                "\(Format.memoryBytes(snapshot.memory.usedBytes)) / \(Format.memoryBytes(snapshot.memory.totalBytes))",
                fraction: snapshot.memory.fraction, tint: Palette.memory)
            if memoryProcesses {
                processList(snapshot.processes.sorted { $0.memoryBytes > $1.memoryBytes }) { p in
                    Format.memoryBytes(p.memoryBytes)
                }
            }
        }
    }

    // MARK: Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderRow(symbol: "internaldrive", title: Loc.t(.disk),
                             value: Format.percent(snapshot.disk.fraction), tint: Palette.disk)
            detailBar("\(Format.bytes(snapshot.disk.freeBytes)) \(Loc.t(.free))",
                      fraction: snapshot.disk.fraction, tint: Palette.disk)
            HStack(spacing: 12) {
                rateLabel("R", snapshot.disk.readBytesPerSec)
                rateLabel("W", snapshot.disk.writeBytesPerSec)
            }
            if diskProcesses {
                processList(snapshot.processes.filter { $0.diskBytesPerSec > 0 }
                    .sorted { $0.diskBytesPerSec > $1.diskBytesPerSec }) { p in
                    Format.rate(p.diskBytesPerSec)
                }
            }
        }
    }

    // MARK: Network

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeaderRow(symbol: "network", title: Loc.t(.network)) { EmptyView() }
            HStack(spacing: 10) {
                netCell("arrow.down", Loc.t(.download), snapshot.network.downloadBytesPerSec, Palette.ingress)
                netCell("arrow.up", Loc.t(.upload), snapshot.network.uploadBytesPerSec, Palette.egress)
            }
        }
    }

    /// One half of the network row: a coloured arrow with the direction's rate, sitting
    /// in its own soft tile so download/upload read as two distinct figures.
    private func netCell(_ symbol: String, _ title: String, _ rate: Double, _ tint: Color) -> some View {
        let idle = Format.isZeroRate(rate)
        return HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(idle ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(.caption2))
                    .foregroundStyle(.secondary)
                Text(Format.rate(rate))
                    .font(.system(.callout, weight: .medium).monospacedDigit())
                    .foregroundStyle(idle ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(idle ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(Format.rate(rate))")
    }

    // MARK: Battery

    private func batterySection(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeaderRow(symbol: b.isCharging ? "battery.100.bolt" : batterySymbol(b.charge),
                             title: Loc.t(.battery),
                             value: batteryValue(b),
                             tint: b.charge < 0.2 ? .red : Palette.battery)
            ProgressBar(fraction: b.charge, tint: b.charge < 0.2 ? .red : Palette.battery)
            if b.isPluggedIn {
                HStack(spacing: 4) {
                    Image(systemName: b.isCharging ? "bolt.fill" : "bolt.slash")
                        .font(.system(.caption2))
                        .foregroundStyle(b.isCharging ? .yellow : .secondary)
                        .accessibilityHidden(true)
                    Text(b.isCharging ? Loc.t(.charging) : Loc.t(.notCharging))
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            if lowPower {
                HStack(spacing: 4) {
                    Image(systemName: "leaf.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                    Text(Loc.t(.lowPowerMode))
                        .font(.system(.subheadline))
                        .foregroundStyle(.secondary)
                }
            }
            if nerd, let cycles = b.cycleCount {
                HStack {
                    Text(Loc.t(.cycles)).font(.system(.subheadline)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(cycles)").font(.system(.subheadline).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Helpers

    /// A usage progress bar with a secondary detail line above it.
    private func detailBar(_ detail: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail)
                .font(.system(.subheadline).monospacedDigit())
                .foregroundStyle(.secondary)
            ProgressBar(fraction: fraction, tint: tint)
        }
    }

    /// Value colour for a rate row: dimmed when idle, normal otherwise.
    private func dimmedIfZero(_ bytesPerSec: Double) -> Color {
        Format.isZeroRate(bytesPerSec) ? Color.secondary.opacity(0.45) : .secondary
    }

    /// "R 288 KB/s" style label, dimmed when idle.
    private func rateLabel(_ tag: String, _ bytesPerSec: Double) -> some View {
        let dimmed = Format.isZeroRate(bytesPerSec)
        return HStack(spacing: 4) {
            Text(tag).font(.system(.caption2, weight: .semibold).monospacedDigit())
            Text(Format.rate(bytesPerSec)).font(.system(.subheadline).monospacedDigit())
        }
        .foregroundStyle(dimmed ? .tertiary : .secondary)
    }

    @ViewBuilder
    private func processList(_ processes: [ProcessUsage],
                             value: @escaping (ProcessUsage) -> String) -> some View {
        let top = Array(processes.prefix(topCount))
        if top.isEmpty {
            Text(Loc.t(.collectingProcesses))
                .font(.system(.caption2))
                .foregroundStyle(.tertiary)
        } else {
            VStack(spacing: 3) {
                ForEach(top) { process in
                    HStack(spacing: 6) {
                        processIcon(process)
                        Text(ProcessDisplay.name(pid: process.id, fallbackName: process.name))
                            .font(.system(.subheadline))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(value(process))
                            .font(.system(.subheadline).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func processIcon(_ process: ProcessUsage) -> some View {
        if let icon = ProcessDisplay.icon(pid: process.id, fallbackName: process.name) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "app.dashed")
                .font(.system(.subheadline))
                .foregroundStyle(.tertiary)
                .frame(width: 13, height: 13)
                .accessibilityHidden(true)
        }
    }

    private func batteryValue(_ b: BatteryInfo) -> String {
        var parts = [Format.percent(b.charge)]
        if !b.isCharging, let minutes = b.timeToEmptyMinutes {
            parts.append(Format.duration(minutes: minutes))
        }
        return parts.joined(separator: " · ")
    }

    private func batterySymbol(_ charge: Double) -> String {
        switch charge {
        case ..<0.13: return "battery.0"
        case ..<0.38: return "battery.25"
        case ..<0.63: return "battery.50"
        case ..<0.88: return "battery.75"
        default: return "battery.100"
        }
    }
}

/// Per-core load bars. Up to 14 cores fill the width in one row; more wrap into a
/// centred grid of fixed-width bars, so it stays tidy from an 8-core laptop to a
/// 24-core desktop.
struct CoreBarsView: View {
    let perCore: [Double]

    private let height: CGFloat = 26
    private let wrapThreshold = 14
    private var cores: [(index: Int, load: Double)] {
        Array(perCore.enumerated()).map { ($0.offset, $0.element) }
    }

    var body: some View {
        if perCore.count <= wrapThreshold {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(cores, id: \.index) { core in
                    bar(core.load).frame(maxWidth: .infinity).accessibilityCore(core)
                }
            }
        } else {
            FlowLayout(spacing: 4, lineSpacing: 4) {
                ForEach(cores, id: \.index) { core in
                    bar(core.load).frame(width: 16).accessibilityCore(core)
                }
            }
        }
    }

    private func bar(_ load: Double) -> some View {
        let value = max(0.05, min(1, load))
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.6))
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [color(load).opacity(0.7), color(load)],
                                     startPoint: .bottom, endPoint: .top))
                .frame(height: height * value)
        }
        .frame(height: height)
    }

    private func color(_ load: Double) -> Color {
        switch load {
        case ..<0.5: return .blue
        case ..<0.8: return .orange
        default: return .red
        }
    }
}

private extension View {
    /// VoiceOver label/value for a single core bar (the bar height already conveys load
    /// visually, so colour isn't the only signal; this adds it for VoiceOver too).
    func accessibilityCore(_ core: (index: Int, load: Double)) -> some View {
        accessibilityElement()
            .accessibilityLabel("\(Loc.t(.cpu)) \(core.index + 1)")
            .accessibilityValue(Format.percent(core.load))
    }
}
