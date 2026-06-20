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
        let allowed = frame.maxX - notchTrailingX

        // Width of what we're showing right now, used as the anti-oscillation reference below.
        let shownWidth = width(keep: metrics.count - lastHidden, metrics: metrics,
                               snapshot: snapshot, mode: mode, display: display)

        // Largest number of trailing cells that fits. `keep == 0` means none fit → show warning.
        var keep = metrics.count
        while keep > 0 {
            let w = width(keep: keep, metrics: metrics, snapshot: snapshot, mode: mode, display: display)
            let expanding = (metrics.count - keep) < lastHidden
            // Showing *more* than we do now must clear `allowed` with room to spare: our item
            // grows by (w - shownWidth), and under heavy overflow macOS shifts our anchor by
            // roughly that much, eating back into `allowed`. Budget for it so the wider state
            // still fits — otherwise the decision flip-flops forever (expand → no room → collapse
            // → room again → expand …). Collapsing only frees room, so plain width is enough.
            let needed = expanding ? (2 * w - shownWidth) : w
            if needed <= allowed { break }
            keep -= 1
        }
        lastHidden = metrics.count - keep
        return lastHidden
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

    /// Point width of the rendered cells (matching `MenuBarLabel`'s own rendering exactly).
    private func measuredWidth(_ metrics: [BarMetric], snapshot: MetricsSnapshot,
                               mode: BarValueMode, display: BarDisplayMode, ellipsis: Bool) -> CGFloat {
        let renderer = ImageRenderer(content:
            BarLabelView(snapshot: snapshot, metrics: metrics, mode: mode,
                         display: display, leadingEllipsis: ellipsis)
                .padding(.horizontal, 1))
        return renderer.nsImage?.size.width ?? 0
    }
}
