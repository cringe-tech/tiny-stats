import Foundation
import FanControlShared

// Installs / removes the privileged fan helper without a Developer ID: a one-time admin-password
// prompt (via osascript `do shell script … with administrator privileges`) copies the helper into
// place and bootstraps it as a LaunchDaemon. This is the unsigned path the user chose; the helper
// itself enforces all hardware safety, so even this loose install can't drive fans unsafely.

public enum HelperError: Error, Equatable {
    case helperMissing            // bundled helper binary not found
    case cancelled                // user dismissed the password prompt
    case failed(String)           // script/osascript error
}

public enum HelperInstaller {
    public static let daemonLabel = FanHelper.machServiceName        // "com.cringetech.tinystats.fanhelper"
    static let plistPath = "/Library/LaunchDaemons/\(FanHelper.machServiceName).plist"
    static let installDir = "/Library/Application Support/TinyStats"
    static let installedHelperPath = "/Library/Application Support/TinyStats/fanhelper"

    /// Installed iff the LaunchDaemon plist and the helper binary are both present.
    public static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: plistPath) && fm.fileExists(atPath: installedHelperPath)
    }

    /// Path to the helper binary shipped next to the main executable (Contents/MacOS in the
    /// packaged app, the build dir under `swift run`). Returns nil if not found.
    public static func bundledHelperPath() -> String? {
        guard let dir = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
        let path = dir.appendingPathComponent("TinyStatsFanHelper").path
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    // MARK: Install / uninstall

    public static func install() -> Result<Void, HelperError> {
        guard let src = bundledHelperPath() else { return .failure(.helperMissing) }
        // Stage the LaunchDaemon plist in a temp file so the privileged script just copies it
        // into place (avoids fragile heredoc quoting inside the AppleScript shell command).
        let tmpPlist = NSTemporaryDirectory() + "tinystats-fanhelper-\(UUID().uuidString).plist"
        do {
            try launchDaemonPlist().write(toFile: tmpPlist, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.failed("could not stage plist: \(error.localizedDescription)"))
        }
        defer { try? FileManager.default.removeItem(atPath: tmpPlist) }

        let script = """
        set -e
        mkdir -p "\(installDir)"
        cp "\(src)" "\(installedHelperPath)"
        chown root:wheel "\(installedHelperPath)"
        chmod 755 "\(installedHelperPath)"
        cp "\(tmpPlist)" "\(plistPath)"
        chown root:wheel "\(plistPath)"
        chmod 644 "\(plistPath)"
        launchctl bootout system/\(daemonLabel) 2>/dev/null || true
        launchctl bootstrap system "\(plistPath)"
        """
        return runPrivileged(script, prompt: "TinyStats needs your password to install the fan-control helper.")
    }

    public static func uninstall() -> Result<Void, HelperError> {
        let script = """
        launchctl bootout system/\(daemonLabel) 2>/dev/null || true
        rm -f "\(plistPath)"
        rm -f "\(installedHelperPath)"
        """
        return runPrivileged(script, prompt: "TinyStats needs your password to remove the fan-control helper.")
    }

    // MARK: Privileged execution

    /// Runs a shell script as root via a single admin-password prompt. The script is staged to a
    /// temp file and executed with `/bin/bash`, so we don't have to escape it into AppleScript.
    private static func runPrivileged(_ script: String, prompt: String) -> Result<Void, HelperError> {
        let tmpScript = NSTemporaryDirectory() + "tinystats-install-\(UUID().uuidString).sh"
        do {
            try ("#!/bin/bash\n" + script + "\n").write(toFile: tmpScript, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.failed("could not stage script: \(error.localizedDescription)"))
        }
        defer { try? FileManager.default.removeItem(atPath: tmpScript) }

        let appleScript = "do shell script \"/bin/bash \" & quoted form of \"\(tmpScript)\" "
            + "with prompt \"\(prompt)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        if proc.terminationStatus == 0 { return .success(()) }
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // osascript returns -128 / "User canceled" when the password dialog is dismissed.
        if errText.contains("-128") || errText.localizedCaseInsensitiveContains("cancel") {
            return .failure(.cancelled)
        }
        return .failure(.failed(errText.isEmpty ? "exit \(proc.terminationStatus)" : errText.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private static func launchDaemonPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(daemonLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(installedHelperPath)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(FanHelper.machServiceName)</key>
                <true/>
            </dict>
        </dict>
        </plist>
        """
    }
}
