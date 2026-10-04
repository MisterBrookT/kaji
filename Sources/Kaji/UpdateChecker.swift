import Foundation
import Combine
import KajiCore

// MARK: - UpdateChecker
//
// Lightweight, privacy-respecting update check for an UNSIGNED menubar app.
//
// On launch (and at most once per `minInterval`) it downloads the static
// `update.json` manifest attached to the latest GitHub release and compares it to this bundle's version.
// If a newer one exists it publishes `available`, which drives a passive cue:
// a dot on the menubar glyph + an "Update to vX" item in the popover.
//
// Explicit actions use Sparkle's signed binary feed on configured .app hosts;
// source builds remain the legacy/unconfigured fallback. Sparkle Ed25519
// signatures secure updates independently of Apple Developer ID/notarization,
// which are still required for a warning-free browser-downloaded first install.
// Passive checks use public GitHub assets, never api.github.com. Sparkle checks
// are manual; automatic downloads and system-profile submission are disabled.
@MainActor
final class UpdateChecker: ObservableObject {
    static let repo = "MisterBrookT/kaji"

    struct Release: Equatable {
        let version: String   // normalized, e.g. "0.4.6"
        let tag: String       // raw tag, e.g. "v0.4.6"
        let url: URL          // release html_url
        let assetURL: URL?    // Kaji.app.zip
        var notes: ReleaseNotes = ReleaseNotes()  // parsed release body
        /// Full 40-hex commit the release was built from; nil when only the redirect is known.
        var sourceRevision: String? = nil
    }

    /// nil = up to date / unknown; non-nil = a strictly newer release exists.
    @Published private(set) var available: Release?
    /// Shared presentation state lets the footer reuse an existing Settings window.
    @Published var reviewingRelease: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isInstalling = false
    @Published private(set) var installError: String?
    @Published private(set) var installLogURL: URL?

    private let installer: SourceUpdateInstaller
    private let binaryUpdater: BinaryUpdatePresenting?
    private let installationDefaults: UserDefaults
    private static let pendingLogKey = "pendingSourceUpdateLog"
    private let session: URLSession
    private let currentVersionOverride: String?
    private var lastCheck: Date?
    private var inFlight = false
    private let minInterval: TimeInterval = 6 * 3600

    /// `available` seeds a deterministic fixture (tests, snapshots) with no network.
    /// `session` and `currentVersion` are injectable so network tests stay deterministic.
    init(available: Release? = nil,
         session: URLSession = URLSession(configuration: .ephemeral),
         currentVersion: String? = nil,
         installer: SourceUpdateInstaller = SourceUpdateInstaller(),
         installationDefaults: UserDefaults = .standard,
         binaryUpdater: BinaryUpdatePresenting? = SparkleBinaryUpdater()) {
        self.binaryUpdater = binaryUpdater
        self.available = available
        self.session = session
        self.currentVersionOverride = currentVersion
        self.installer = installer
        self.installationDefaults = installationDefaults
        restoreInstallationResult()
    }

    /// True when explicit update actions go to the native binary updater
    /// instead of the source-build sheet.
    var usesBinaryUpdater: Bool { binaryUpdater?.isAvailable == true }

    /// Starts the native update flow. Returns false when the caller must use
    /// the source fallback. The binary updater owns quit/relaunch.
    @discardableResult
    func presentBinaryUpdateCheck() -> Bool {
        guard let binaryUpdater, binaryUpdater.isAvailable else { return false }
        binaryUpdater.checkForUpdates()
        return true
    }

    var currentVersion: String {
        currentVersionOverride
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Static manifest asset uploaded with each release; served without API rate limits.
    static let manifestURL = URL(string: "https://github.com/\(repo)/releases/latest/download/update.json")!
    /// Public page; GitHub redirects it to `/releases/tag/<tag>` without API rate limits.
    static let latestPageURL = URL(string: "https://github.com/\(repo)/releases/latest")!

    /// Start a check unless one ran within `minInterval` (use force from a
    /// manual "Check for updates" action).
    func checkIfDue(force: Bool = false) {
        if !force, let last = lastCheck, Date().timeIntervalSince(last) < minInterval { return }
        lastCheck = Date()
        Task { await check() }
    }

    func check() async {
        // Coalesce concurrent checks (e.g. rapid "Check for Updates" clicks) into
        // a single in-flight request. Safe to read/write unguarded: @MainActor.
        if inFlight { return }
        inFlight = true
        isChecking = true
        lastError = nil
        defer {
            inFlight = false
            isChecking = false
        }
        let manifestFailure: String
        switch await fetchManifest() {
        case .success(let release):
            apply(release)
            return
        case .invalid(let detail):
            // A manifest was served but fails validation: fail closed rather than
            // letting the redirect fallback paper over a tampered or broken feed.
            lastError = "invalid update manifest: \(detail)"
            return
        case .failure(let detail):
            manifestFailure = detail
        }
        // Manifest missing (e.g. older release without update.json) or unreachable:
        // fall back to the public releases/latest redirect. Notes are unknown there.
        switch await fetchFromRedirect() {
        case .success(let release):
            apply(release)
        case .failure(let detail), .invalid(let detail):
            lastError = "manifest: \(manifestFailure); fallback: \(detail)"
        }
    }

    private enum FetchResult {
        case success(Release)
        /// Transport or HTTP unavailability; eligible for the redirect fallback.
        case failure(String)
        /// Served content failed validation; never falls back.
        case invalid(String)
    }

    private func apply(_ release: Release) {
        available = Self.isNewer(release.version, than: Self.normalize(currentVersion)) ? release : nil
        lastChecked = Date()
    }

    private func fetchManifest() async -> FetchResult {
        var req = URLRequest(url: Self.manifestURL)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("Kaji", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 12
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure("no HTTP response") }
            guard http.statusCode == 200 else { return .failure("HTTP \(http.statusCode)") }
            switch Self.parseManifest(data) {
            case .success(let release): return .success(release)
            case .failure(let error): return .invalid(error.detail)
            }
        } catch {
            return .failure("network: \(error.localizedDescription)")
        }
    }

    struct ManifestError: Error, Equatable { let detail: String }

    /// Validates schema v1: `{schemaVersion, version, tag, releaseURL, sourceRevision, notes}`.
    /// The tag must be exactly `v<version>` (stable x.y.z), the URL the canonical
    /// release page for that tag in this repo, and the revision a full lowercase SHA-1.
    static func parseManifest(_ data: Data) -> Result<Release, ManifestError> {
        func fail(_ s: String) -> Result<Release, ManifestError> { .failure(ManifestError(detail: s)) }
        guard data.count <= 1_048_576 else { return fail("manifest exceeds 1 MB") }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return fail("JSON is not an object")
        }
        guard let schema = obj["schemaVersion"] as? NSNumber,
              CFGetTypeID(schema) == CFNumberGetTypeID(), schema == 1 else {
            return fail("schemaVersion must be the number 1")
        }
        guard let version = obj["version"] as? String, isStableSemver(version) else {
            return fail("tag/version must be a stable x.y.z version")
        }
        guard let tag = obj["tag"] as? String, tag == "v\(version)" else {
            return fail("tag must equal v\(version)")
        }
        let canonical = "https://github.com/\(repo)/releases/tag/\(tag)"
        guard let rawURL = obj["releaseURL"] as? String, rawURL == canonical,
              let url = URL(string: rawURL), releaseTag(fromFinalURL: url) == tag else {
            return fail("releaseURL must be \(canonical)")
        }
        guard let revision = obj["sourceRevision"] as? String, revision.count == 40,
              revision.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }) else {
            return fail("sourceRevision must be a 40-character lowercase hex commit")
        }
        guard let notes = obj["notes"] as? String else { return fail("notes must be a string") }
        return .success(Release(version: version, tag: tag, url: url, assetURL: nil,
                                notes: ReleaseNotes.parse(notes), sourceRevision: revision))
    }

    private static func isStableSemver(_ v: String) -> Bool {
        let parts = v.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { p in
            !p.isEmpty && Int(p) != nil && p.allSatisfy({ $0 >= "0" && $0 <= "9" }) && (p == "0" || p.first != "0")
        }
    }

    private func fetchFromRedirect() async -> FetchResult {
        var req = URLRequest(url: Self.latestPageURL)
        req.httpMethod = "HEAD"
        req.setValue("Kaji", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 12
        do {
            let (_, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .failure("no HTTP response") }
            guard http.statusCode == 200 else { return .failure("HTTP \(http.statusCode)") }
            guard let final = http.url, let tag = Self.releaseTag(fromFinalURL: final) else {
                return .failure("unexpected redirect target \(http.url?.absoluteString ?? "nil")")
            }
            return .success(Release(version: Self.normalize(tag), tag: tag, url: final, assetURL: nil))
        } catch {
            return .failure("network: \(error.localizedDescription)")
        }
    }

    /// Accepts only `https://github.com/<repo>/releases/tag/<tag>` with a version-like tag.
    static func releaseTag(fromFinalURL url: URL) -> String? {
        guard url.scheme == "https", url.host?.lowercased() == "github.com",
              url.port == nil, url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        let repoParts = repo.split(separator: "/").map(String.init)
        guard parts.count == 5,
              parts[0].lowercased() == repoParts[0].lowercased(),
              parts[1].lowercased() == repoParts[1].lowercased(),
              parts[2] == "releases", parts[3] == "tag" else { return nil }
        let tag = parts[4].removingPercentEncoding ?? parts[4]
        let version = (tag.first == "v" || tag.first == "V") ? String(tag.dropFirst()) : tag
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0 >= "0" && $0 <= "9" }) })
        else { return nil }
        return tag
    }

    enum InstallError: Error, Equatable, LocalizedError {
        case alreadyInstalling, invalidRelease
        var errorDescription: String? {
            switch self {
            case .alreadyInstalling: "An update is already being built."
            case .invalidRelease: "The approved release version, tag and repository URL do not match."
            }
        }
    }

    /// Build and verify before handing off. The caller quits only on success.
    func install(_ release: Release) async throws {
        guard !isInstalling else { throw InstallError.alreadyInstalling }
        isInstalling = true
        installError = nil
        installLogURL = installer.logURL
        defer { isInstalling = false }
        do {
            guard Self.isStableSemver(release.version), release.tag == "v\(release.version)",
                  release.url.absoluteString == "https://github.com/\(Self.repo)/releases/tag/\(release.tag)"
            else { throw InstallError.invalidRelease }
            let prepared = try await installer.prepare(tag: release.tag, version: release.version,
                                                       revision: release.sourceRevision)
            installationDefaults.set(installer.logURL.path, forKey: Self.pendingLogKey)
            try installer.launchReplacement(prepared)
        } catch {
            installationDefaults.removeObject(forKey: Self.pendingLogKey)
            let tail = (try? String(contentsOf: installer.logURL, encoding: .utf8))?
                .split(separator: "\n").suffix(8).joined(separator: "\n")
            installError = [error.localizedDescription, tail].compactMap { $0 }.joined(separator: "\n")
            throw error
        }
    }

    private func restoreInstallationResult(retriesRemaining: Int = 3) {
        guard let path = installationDefaults.string(forKey: Self.pendingLogKey) else { return }
        let log = URL(fileURLWithPath: path)
        installLogURL = log
        let result = try? String(contentsOf: log.appendingPathExtension("result"), encoding: .utf8)
        let status = result?.trimmingCharacters(in: .whitespacesAndNewlines)
        if status == "launching", retriesRemaining > 0 {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.restoreInstallationResult(retriesRemaining: retriesRemaining - 1)
            }
            return
        }
        if status != "success" {
            installError = "The previous update did not complete. See the installation log."
        }
        installationDefaults.removeObject(forKey: Self.pendingLogKey)
    }

    // "v0.4.6" -> "0.4.6", "v0.4.6-beta.1" -> "0.4.6". (Pre-releases are already
    // rejected by manifest/redirect validation, so this only hardens the comparison.)
    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.first == "v" || t.first == "V" { t.removeFirst() }
        if let dash = t.firstIndex(of: "-") { t = String(t[..<dash]) }
        return t
    }

    /// Semver-ish compare on dot-separated integer components (missing = 0).
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

}
