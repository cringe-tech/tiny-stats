import SwiftUI
import AppKit
import TinyStatsCore

/// Works out how many menu-bar cells fit before a notch clips the status item, so we can drop
/// the leftmost cells ourselves instead of letting macOS hide the whole item without warning.
///
/// macOS exposes no "you are hidden" or "remaining width" API, but two public facts are enough:
///   • our status item lives in a window of class `NSStatusBarWindow`, whose screen frame we can
///     read — its right edge (`maxX`) is fixed by the items to our right, independent of our own
///     width, so it's a stable anchor;
///   • `NSScreen.auxiliaryTopRightArea.minX` is the notch's trailing edge — the leftmost x our
///     item may occupy. The room we have is therefore `maxX - notchTrailingX`.
@MainActor
final class MenuBarFit {
    private var observedWindow: NSWindow?
    private var onFrameChange: (() -> Void)?
    /// Last computed value, returned when the item isn't measurable yet, to avoid flicker.
    private var lastHidden = 0
    /// When expanding would still leave at least this much free space beside the item, we treat
    /// it as a genuine gap (not a wedge against the notch) and reclaim it, bypassing the stricter
    /// anti-oscillation budget. Sized below a single cell so a real gap clears it but the razor's
    /// edge near the notch does not.
    private static let expandSlack: CGFloat = 22

    /// Registers a handler fired when the status item moves or resizes — which happens when a
    /// neighbouring menu-bar item appears or disappears, changing how much room we have.
    func observe(_ handler: @escaping () -> Void) { onFrameChange = handler }

    /// Number of leftmost cells that must be dropped so the item stops short of the notch.
    ///
    /// Returns a value equal to `metrics.count` when not even one cell fits — the caller then
    /// renders a compact overflow warning (see `MenuBarOverflow`).
    func hiddenCount(metrics: [BarMetric], snapshot: MetricsSnapshot,
                     mode: BarValueMode, display: BarDisplayMode) -> Int {
        attachObserverIfNeeded()
        guard !metrics.isEmpty,
              let frame = statusFrame(),
              let notchTrailingX = NSScreen.main?.auxiliaryTopRightArea?.minX else { lastHidden = 0; return 0 }
        // Ignore a not-yet-placed item (during launch macOS briefly parks the status window at
        // the left edge); a real item always sits to the right of the notch.
        guard frame.maxX > notchTrailingX else { return lastHidden }

        // Left limit our cells must clear: whichever is further right, the notch or the trailing
        // edge of the nearest neighbour wedged between us and the notch. Measuring only to the notch
        // over-counts the room by that neighbour's footprint — we'd render too wide, macOS would
        // hide the whole item, and next tick the room "frees up" and we expand again. A flip-flop.
        let leftBoundary = max(notchTrailingX, neighbourBoundary(frame: frame))
        let allowed = frame.maxX - leftBoundary

        // The status item is wider on screen than the image we rasterise: macOS adds fixed chrome
        // around it (~13pt). Measure that gap from the live frame once and fold it into every
        // candidate, or our estimate runs short and we overflow the notch by exactly that much.
        let currentKeep = max(0, metrics.count - lastHidden)
        let currentWidth = width(keep: currentKeep, metrics: metrics,
                                 snapshot: snapshot, mode: mode, display: display)
        let pad = max(0, frame.width - currentWidth)

        // Width of what we're showing right now, used as the anti-oscillation reference below.
        let shownWidth = currentWidth + pad

        // Largest number of trailing cells that fits. `keep == 0` means none fit → show warning.
        var keep = metrics.count
        while keep > 0 {
            let w = width(keep: keep, metrics: metrics, snapshot: snapshot, mode: mode, display: display) + pad
            let expanding = (metrics.count - keep) < lastHidden
            // Showing *more* than we do now normally must clear `allowed` with room to spare: our
            // item grows by (w - shownWidth), and under heavy overflow (wedged against the notch)
            // macOS shifts our anchor by roughly that much, eating back into `allowed`. Budgeting
            // for it (the doubled term) avoids an expand → no room → collapse → room again flip-flop.
            //
            // But that over-counts when there's a clear gap beside us: if the cell still leaves a
            // comfortable margin (`expandSlack`), we aren't wedged, the anchor won't move, and the
            // doubled budget would otherwise strand the cell hidden with empty space next to it.
            let fits = expanding
                ? ((2 * w - shownWidth) <= allowed || (allowed - w) >= Self.expandSlack)
                : (w <= allowed)
            if fits { break }
            keep -= 1
        }
        lastHidden = metrics.count - keep
        return lastHidden
    }

    /// Trailing x of the nearest menu-bar item sitting between us and the notch, or `0` when there
    /// is none. Detection via `CGWindowListCopyWindowInfo` is occasionally a frame late (the
    /// neighbour blinks out of one snapshot), so we hold the last sighting for a few ticks: a
    /// boundary that flickered notch↔neighbour would itself drive the oscillation we're killing.
    private var stickyNeighbourMaxX: CGFloat = 0
    private var neighbourTTL = 0
    private func neighbourBoundary(frame: CGRect) -> CGFloat {
        let detected = menuBarNeighbourMaxXs()
            .filter { $0 > 0 && $0 <= frame.minX + 2 }   // strictly to our left
            .max()
        if let detected {
            stickyNeighbourMaxX = detected
            neighbourTTL = 5
            return detected
        }
        // Hold the last sighting briefly — but only while it's still genuinely to our left. The
        // item parks at the far right for a frame during launch (and can jump on relayout); a
        // boundary captured there would sit to our *right* once we settle, driving `allowed`
        // negative and collapsing us to the warning for no reason. Drop it the moment it's stale.
        if neighbourTTL > 0, stickyNeighbourMaxX <= frame.minX + 2 {
            neighbourTTL -= 1
            return stickyNeighbourMaxX
        }
        stickyNeighbourMaxX = 0
        neighbourTTL = 0
        return 0
    }

    /// Trailing x of every on-screen window sitting in the menu-bar row (thin, pinned to the top),
    /// across all apps. X coordinates match `NSWindow.frame` directly (only Y is flipped between
    /// the two coordinate systems), so these can be compared with our status item's `minX` as-is.
    /// Read-only geometry — `CGWindowListCopyWindowInfo` needs no screen-recording permission.
    private func menuBarNeighbourMaxXs() -> [CGFloat] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var result: [CGFloat] = []
        for info in list {
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            // Menu-bar items hug the top and are short; this drops normal windows cheaply.
            guard bounds.minY < 40, bounds.height < 40, bounds.width > 0 else { continue }
            result.append(bounds.maxX)
        }
        return result
    }

    /// Rendered point width for the trailing `keep` cells, or — when `keep <= 0` — the compact
    /// overflow-warning glyph that stands in when no cell fits.
    private func width(keep: Int, metrics: [BarMetric], snapshot: MetricsSnapshot,
                       mode: BarValueMode, display: BarDisplayMode) -> CGFloat {
        guard keep > 0 else { return MenuBarOverflow.width }
        return measuredWidth(Array(metrics.suffix(keep)), snapshot: snapshot,
                             mode: mode, display: display, ellipsis: keep < metrics.count)
    }

    private func statusFrame() -> CGRect? {
        NSApp.windows.first { $0.isVisible && Self.isStatusBarWindow($0) }?.frame
    }

    private func attachObserverIfNeeded() {
        guard observedWindow == nil,
              let window = NSApp.windows.first(where: Self.isStatusBarWindow) else { return }
        observedWindow = window
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onFrameChange?() }
            }
        }
    }

    private static func isStatusBarWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)) == "NSStatusBarWindow"
    }

    /// Rasterising a SwiftUI view via `ImageRenderer` is expensive and `hiddenCount` measures
    /// several candidate widths per call — many of them identical across ticks (idle values) or
    /// even within a single call. Memoise on a signature that fully determines the render, so a
    /// repeat is a dictionary hit instead of another rasterisation. Keyed exactly, so it can never
    /// return a stale width; capped so it stays bounded.
    private var widthCache: [String: CGFloat] = [:]

    /// Point width of the rendered cells (matching `MenuBarLabel`'s own rendering exactly).
    private func measuredWidth(_ metrics: [BarMetric], snapshot: MetricsSnapshot,
                               mode: BarValueMode, display: BarDisplayMode, ellipsis: Bool) -> CGFloat {
        let key = BarLabelView.widthSignature(metrics: metrics, snapshot: snapshot,
                                              mode: mode, display: display, leadingEllipsis: ellipsis)
        if let cached = widthCache[key] { return cached }
        let renderer = ImageRenderer(content:
            BarLabelView(snapshot: snapshot, metrics: metrics, mode: mode,
                         display: display, leadingEllipsis: ellipsis)
                .padding(.horizontal, 1))
        let width = renderer.nsImage?.size.width ?? 0
        if widthCache.count > 128 { widthCache.removeAll(keepingCapacity: true) }
        widthCache[key] = width
        return width
    }
}
