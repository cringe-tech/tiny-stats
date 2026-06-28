import Foundation
import Darwin

/// Severity of a log line. Rendered as a fixed-width tag so the file stays grep-friendly.
public enum LogLevel: String, Sendable {
    case info = "INFO "
    case warning = "WARN "
    case error = "ERROR"
}

/// A tiny file logger so users can see what the app is doing and hand the log to the
/// developer for diagnosis. Lines are appended synchronously (no in-memory buffer) so a
/// crash never loses the trail leading up to it. The active file is capped at 50 MB; when
/// it overflows it rolls over to a single `-previous` backup, so disk use stays bounded.
public enum Log {
    /// `~/Library/Logs/TinyStats` — the conventional, Console.app-visible spot.
    public static let directory: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return library.appendingPathComponent("Logs/TinyStats", isDirectory: true)
    }()

    public static let fileURL = directory.appendingPathComponent("tinystats.log")
    public static let previousURL = directory.appendingPathComponent("tinystats-previous.log")

    private static let maxBytes: UInt64 = 50 * 1024 * 1024

    /// Serialises every write and lazily owns the open file handle.
    private static let queue = DispatchQueue(label: "com.cringetech.tinystats.log")

    // Both are only mutated/used on `queue` (crash handlers read `handle` best-effort), so the
    // serial queue — not the type system — provides the synchronisation.
    nonisolated(unsafe) private static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = .current
        return f
    }()

    nonisolated(unsafe) private static var handle: FileHandle? = {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: fileURL)
        _ = try? h?.seekToEnd()
        return h
    }()

    // MARK: Public API

    public static func info(_ message: @autoclosure () -> String) { write(.info, message()) }
    public static func warning(_ message: @autoclosure () -> String) { write(.warning, message()) }
    public static func error(_ message: @autoclosure () -> String) { write(.error, message()) }

    /// Best-effort combined text of previous + current logs, oldest first, for export.
    public static func combinedText() -> String {
        queue.sync { try? handle?.synchronize() }
        let previous = (try? String(contentsOf: previousURL, encoding: .utf8)) ?? ""
        let current = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        return previous + current
    }

    // MARK: Writing

    private static func write(_ level: LogLevel, _ message: String) {
        let now = Date()
        queue.async {
            let line = "\(timestamp.string(from: now)) [\(level.rawValue)] \(message)\n"
            guard let data = line.data(using: .utf8), let h = handle else { return }
            try? h.write(contentsOf: data)
            rotateIfNeeded()
        }
    }

    /// Rolls the active file over to `-previous` once it crosses the size cap. Runs on `queue`.
    private static func rotateIfNeeded() {
        guard let size = try? handle?.offset(), size > maxBytes else { return }
        try? handle?.close()
        try? FileManager.default.removeItem(at: previousURL)
        try? FileManager.default.moveItem(at: fileURL, to: previousURL)
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
    }

    // MARK: Crash capture

    /// Routes uncaught Obj-C exceptions and fatal signals into the log so a crash leaves a
    /// visible trail. Call once, early, at launch.
    public static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            Log.error("Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "nil")\n\(stack)")
            // Give the async write a moment to land before the process tears down.
            Log.queue.sync { try? Log.handle?.synchronize() }
        }

        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            signal(sig) { received in
                // Async-signal-safe: write a constant marker straight to the open fd, then
                // restore the default handler and re-raise so the OS still produces its report.
                if let fd = Log.handle?.fileDescriptor {
                    let marker = "\n*** TinyStats received fatal signal — see system crash report ***\n"
                    _ = marker.withCString { Darwin.write(fd, $0, strlen($0)) }
                }
                signal(received, SIG_DFL)
                raise(received)
            }
        }
    }
}
