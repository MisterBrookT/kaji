import AppKit
import Foundation
import Sparkle

/// Presents the native binary update flow for the installed .app.
@MainActor
protocol BinaryUpdatePresenting: AnyObject {
    var isAvailable: Bool { get }
    func checkForUpdates()
}

/// Sparkle is only usable from a real .app whose Info.plist carries a valid
/// EdDSA public key and a canonical HTTPS appcast URL. Anything else (the
/// `swift test` xctest host, `swift run`, a misconfigured bundle) stays inactive.
struct SparkleBundleConfiguration: Equatable {
    let feedURL: URL
    let publicEDKey: String

    static func validated(bundleURL: URL, info: [String: Any]?) -> SparkleBundleConfiguration? {
        guard bundleURL.pathExtension == "app", let info else { return nil }
        guard let key = info["SUPublicEDKey"] as? String, isValidPublicEDKey(key) else { return nil }
        guard let feed = info["SUFeedURL"] as? String, let url = canonicalHTTPSURL(feed) else { return nil }
        return SparkleBundleConfiguration(feedURL: url, publicEDKey: key)
    }

    static func isValidPublicEDKey(_ key: String) -> Bool {
        guard key == key.trimmingCharacters(in: .whitespacesAndNewlines),
              let data = Data(base64Encoded: key) else { return false }
        return data.count == 32
    }

    static func canonicalHTTPSURL(_ string: String) -> URL? {
        guard string == string.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: string),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil,
              let url = components.url,
              url.absoluteString == string else { return nil }
        return url
    }
}

@MainActor
final class SparkleBinaryUpdater: NSObject, BinaryUpdatePresenting {
    private var controller: SPUStandardUpdaterController?
    private let configured: Bool
    private var started = false

    init(bundle: Bundle = .main) {
        configured = SparkleBundleConfiguration.validated(bundleURL: bundle.bundleURL,
                                                          info: bundle.infoDictionary) != nil
        super.init()
    }

    var isAvailable: Bool { configured }

    func checkForUpdates() {
        guard configured else { return }
        // Construct lazily: Sparkle's preference setters persist values in the
        // host domain. Startup and passive/offscreen renders must not write them.
        if controller == nil {
            let newController = SPUStandardUpdaterController(startingUpdater: false,
                                                             updaterDelegate: nil,
                                                             userDriverDelegate: nil)
            newController.updater.automaticallyChecksForUpdates = false
            newController.updater.automaticallyDownloadsUpdates = false
            newController.updater.sendsSystemProfile = false
            controller = newController
        }
        guard let controller else { return }
        // LSUIElement apps are not active after a status-item click; Sparkle's
        // window would otherwise open behind other apps.
        NSApp.activate(ignoringOtherApps: true)
        if !started {
            controller.startUpdater()
            started = true
        }
        controller.checkForUpdates(nil)
    }
}
