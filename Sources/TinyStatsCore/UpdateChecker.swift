import Foundation

/// Result of a release check.
public enum UpdateStatus: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed
}

/// Lightweight update check against the latest GitHub Release. No auto-install: an
/// available update points at the release/asset URL for a manual (drag-to-Applications)
/// install — the only safe path for an ad-hoc-signed build. Network + comparison are
/// kept pure here so they're easy to test.
public enum UpdateChecker {
    // Set these once the open-source repo exists; the check no-ops until then.
    public static let owner = "cringe-tech"
    public static let repo = "tiny-stats"
    public static var isConfigured: Bool { owner != "OWNER" && repo != "REPO" }

    public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Homebrew

    /// Homebrew cask token and tap, used to build the upgrade command.
    public static let caskToken = "tinystats"
    public static let caskTap = "cringe-tech/apps"

    /// Fully-qualified upgrade command — works whether or not the tap is already tapped.
    public static var brewUpgradeCommand: String {
        "brew upgrade --cask \(caskTap)/\(caskToken)"
    }

    /// True when this build is the Homebrew-cask copy: the cask keeps a `Caskroom/<token>`
    /// directory under the brew prefix, and installs the app into `/Applications`. Requiring
    /// both avoids treating a hand-placed copy as brew-managed just because the cask exists.
    public static var installedViaHomebrew: Bool {
        let fm = FileManager.default
        let caskroomExists = ["/opt/homebrew", "/usr/local"].contains {
            fm.fileExists(atPath: "\($0)/Caskroom/\(caskToken)")
        }
        return caskroomExists && Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// Dotted version compare: true iff `a` is strictly newer than `b` (e.g. 0.10.0 > 0.9.0).
    public static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    public static func fetchLatest() async -> UpdateStatus {
        guard isConfigured,
              let api = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
        else { return .idle }

        var request = URLRequest(url: api)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data)
            else { return .failed }

            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            guard isNewer(latest, than: currentVersion) else { return .upToDate }
            guard let url = release.downloadURL ?? URL(string: release.html_url) else { return .failed }
            return .available(version: latest, url: url)
        } catch {
            return .failed
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }

        /// Prefer a .dmg, then a .zip; nil if no installable asset is attached.
        var downloadURL: URL? {
            let preferred = assets.first { $0.name.lowercased().hasSuffix(".dmg") }
                ?? assets.first { $0.name.lowercased().hasSuffix(".zip") }
            return preferred.flatMap { URL(string: $0.browser_download_url) }
        }
    }
}
