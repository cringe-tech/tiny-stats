import SwiftUI
import TinyStatsCore

/// The visual content of the menu bar cells (icons + values). Used directly as the
/// Settings preview, and rasterised by `MenuBarLabel` for the actual menu bar.
struct BarLabelView: View {
    let snapshot: MetricsSnapshot
    let metrics: [BarMetric]
    var mode: BarValueMode = .percent
    var display: BarDisplayMode = .iconValue
    /// Drawn as a leading "…" to signal that cells to the left were dropped for lack of room.
    var leadingEllipsis: Bool = false
    /// While macOS Low Power Mode is on, a leaf is tucked inside the battery cell's icon.
    var lowPower: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if leadingEllipsis {
                Image(systemName: "ellipsis")
            }
            ForEach(metrics.isEmpty ? [.cpu] : metrics) { metric in
                HStack(spacing: 3) {
                    if display.showsIcon {
                        icon(metric)
                    }
                    if display.showsLabel {
                        Text(metric.label)
                            .font(.system(size: 12, weight: .medium))
                    }
                    if display.showsValue {
                        Text(text(metric))
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                    }
                }
                .fixedSize()
            }
        }
        .fixedSize()   // render at full intrinsic width so cells never truncate
        .lineLimit(1)
    }

    @ViewBuilder
    private func icon(_ metric: BarMetric) -> some View {
        if metric == .battery {
            batteryIcon
        } else {
            Image(systemName: metric.symbol)
        }
    }

    /// The battery cell: a discrete charge-level glyph (`battery.0…100`) so the fill roughly
    /// tracks the real percentage, with a bolt overlaid whenever on mains power (matching macOS,
    /// which shows the bolt while the adapter is connected — even when held at a charge limit and
    /// not actively charging). There is no stock SF Symbol that combines a charge level with a
    /// bolt, hence the overlay.
    ///
    /// In Low Power Mode the fill is tinted yellow (outline + bolt stay black), exactly as macOS
    /// tints its own battery — so it reads as a native state. The palette colours only show in
    /// LPM; otherwise `MenuBarLabel` renders the whole cell as a monochrome template. For the
    /// `battery.X` palette the style order is (fill, outline), verified by rendering each slot in
    /// a distinct colour.
    @ViewBuilder
    private var batteryIcon: some View {
        let b = snapshot.battery
        ZStack {
            if lowPower {
                Image(systemName: batterySymbol(b?.charge ?? 0))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.yellow, .primary)
            } else {
                Image(systemName: batterySymbol(b?.charge ?? 0))
            }
            if b?.isPluggedIn == true {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func text(_ metric: BarMetric) -> String {
        switch metric {
        case .cpu: return Format.percent(snapshot.cpu.total)
        case .gpu: return Format.percent(snapshot.gpu.utilization)
        case .memory:
            return mode == .current
                ? compactBytes(snapshot.memory.usedBytes)
                : Format.percent(snapshot.memory.fraction)
        case .network:
            return "↓\(compactRate(snapshot.network.downloadBytesPerSec))"
        case .disk:
            return "↓\(compactRate(snapshot.disk.readBytesPerSec))"
        case .battery:
            return Format.percent(snapshot.battery?.charge ?? 0)
        }
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

    private func compactBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        return String(format: "%.1fG", gb)
    }

    private func compactRate(_ bytesPerSec: Double) -> String {
        let kb = bytesPerSec / 1024
        if kb < 1000 { return "\(Int(kb))K" }
        return String(format: "%.1fM", kb / 1024)
    }
}

/// Rasterises `BarLabelView` into a template `NSImage` for the menu bar.
///
/// `MenuBarExtra` renders a multi-view SwiftUI label unreliably (it clips to the first
/// element). Rendering to a single template image guarantees all cells and their icons
/// show, and the template makes it adapt to light/dark menu bars automatically.
struct MenuBarLabel: View {
    let snapshot: MetricsSnapshot
    let metrics: [BarMetric]
    let mode: BarValueMode
    let display: BarDisplayMode
    /// How many leftmost cells to drop so the item clears the notch (see `MenuBarFit`).
    var hiddenCount: Int = 0
    /// Whether macOS Low Power Mode is on (tints the battery cell yellow).
    var lowPower: Bool = false
    /// Dark/light of the menu bar, supplied by `AppState` so the cells tint correctly from the
    /// first frame (an in-view read is unreliable before the status-item window exists).
    var menuBarIsDark: Bool = false

    /// The cells actually drawn: the rightmost ones, with at least one always kept.
    private var visibleMetrics: [BarMetric] {
        guard hiddenCount > 0 else { return metrics }
        return Array(metrics.suffix(max(1, metrics.count - hiddenCount)))
    }

    /// We can only show a yellow battery by rendering in colour (template images are forced
    /// monochrome). That's only worth it when the battery cell is actually visible in LPM.
    private var colorize: Bool { lowPower && visibleMetrics.contains(.battery) }

    /// Heavy overflow: not even one cell fits (`MenuBarFit` signals this by hiding every cell).
    /// Show the warning glyph instead of silently vanishing or thrashing.
    private var isOverflowed: Bool { !metrics.isEmpty && hiddenCount >= metrics.count }

    var body: some View {
        Image(nsImage: isOverflowed ? MenuBarOverflow.image() : rendered)
    }

    @MainActor private var rendered: NSImage {
        let renderer = ImageRenderer(
            content: BarLabelView(snapshot: snapshot, metrics: visibleMetrics, mode: mode,
                                  display: display, leadingEllipsis: hiddenCount > 0,
                                  lowPower: colorize)
                .environment(\.colorScheme, menuBarIsDark ? .dark : .light)
                .padding(.horizontal, 1))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage, image.size.width > 0 else {
            // An empty render collapses the status item to nothing — log it so a vanished
            // menu-bar icon can be told apart from macOS hiding it for lack of room.
            Log.error("Menu-bar render produced an empty image (metrics: \(metrics.map(\.rawValue)))")
            return NSImage()
        }
        // Template (monochrome, auto-adapting) normally; colour only to show the yellow battery.
        image.isTemplate = !colorize
        return image
    }
}

/// The compact warning shown in the menu bar when other apps' items crowd ours out and not even
/// one stat cell fits. A single narrow glyph (much smaller than a cell) so it still has a chance
/// to fit, gives the user a visible "free up the menu bar" cue, and — being a fixed minimal size
/// — gives `MenuBarFit` a stable floor to settle on instead of oscillating.
enum MenuBarOverflow {
    @MainActor static func image() -> NSImage {
        let renderer = ImageRenderer(content:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 1))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage, image.size.width > 0 else { return NSImage() }
        image.isTemplate = true   // monochrome, auto-adapts to the menu-bar appearance
        return image
    }

    /// Point width of the warning glyph, so `MenuBarFit` can treat "show the warning" as its
    /// smallest renderable state.
    @MainActor static var width: CGFloat { image().size.width }
}
