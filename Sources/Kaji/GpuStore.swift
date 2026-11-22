import Foundation
import Combine
import KajiCore

// GPU monitor data: read-only poll of mlkit's `~/.mlkit/gpus.json`. No ssh, no
// writes. Runs only while the module is on (AppDelegate.applyModuleLifecycle).
@MainActor
final class GpuStore: ObservableObject {
    @Published private(set) var snapshot: GpuSnapshot?
    @Published private(set) var missing = false

    let url: URL
    private var timer: Timer?
    static let interval: TimeInterval = 30

    init(url: URL = GpuSnapshot.defaultURL, snapshot: GpuSnapshot? = nil) {
        self.url = url
        self.snapshot = snapshot
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reload() {
        guard let data = try? Data(contentsOf: url) else {
            missing = true
            snapshot = nil
            return
        }
        missing = false
        if let s = try? GpuSnapshot.decode(data) { snapshot = s }
    }
}
