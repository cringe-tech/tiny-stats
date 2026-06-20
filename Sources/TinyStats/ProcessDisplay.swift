import AppKit

/// Resolves a pid to a presentable icon and name. App processes get their real
/// icon and localized name via `NSRunningApplication`; everything else falls back
/// to the raw process name with a generic icon. Results are cached per pid so the
/// process list doesn't hit the lookup on every refresh.
@MainActor
enum ProcessDisplay {
    private struct Entry { let icon: NSImage?; let name: String }
    private static var cache: [Int32: Entry] = [:]

    static func icon(pid: Int32, fallbackName: String) -> NSImage? {
        resolve(pid, fallbackName).icon
    }

    static func name(pid: Int32, fallbackName: String) -> String {
        resolve(pid, fallbackName).name
    }

    private static func resolve(_ pid: Int32, _ fallbackName: String) -> Entry {
        if let cached = cache[pid] { return cached }
        let app = NSRunningApplication(processIdentifier: pid)
        let entry = Entry(
            icon: app?.icon,
            name: app?.localizedName ?? fallbackName)
        cache[pid] = entry
        return entry
    }
}
