import XCTest
@testable import Kaji

@MainActor
final class QuotaStoreTests: XCTestCase {
    private func provider(
        _ id: String,
        fiveHourPercent: Double?,
        weekPercent: Double? = nil
    ) -> ProviderView {
        ProviderView(
            id: id,
            mark: id,
            displayName: id,
            fiveHourPercent: fiveHourPercent,
            weekPercent: weekPercent,
            resetDate: nil,
            weekResetDate: nil
        )
    }

    func testOverlappingRefreshAndStopSuppressStaleResult() async {
        let entered = expectation(description: "runner entered")
        let release = DispatchSemaphore(value: 0)
        let calls = LockedCounter()
        let store = QuotaStore(runner: { _ in
            let call = calls.increment()
            if call == 1 { entered.fulfill() }
            release.wait()
            return .failure(call == 1 ? "stale result" : "latest result")
        })
        store.refresh()
        await fulfillment(of: [entered], timeout: 2)
        store.refresh()
        XCTAssertEqual(calls.value, 1)
        store.stop()
        store.refresh()
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(calls.value, 1, "restart must not overlap the stopped worker")
        release.signal()
        // Restart is deferred until the stopped worker releases its slot.
        let next = expectation(description: "new runner entered")
        // The original runner is reused, so release its second call as well.
        release.signal()
        store.refresh()
        for _ in 0..<100 where calls.value < 2 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if calls.value == 2 { next.fulfill() }
        await fulfillment(of: [next], timeout: 2)
        XCTAssertEqual(calls.value, 2)
        for _ in 0..<100 where store.lastError == nil {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(store.lastError, "latest result")
    }

    func testExecutorDrainsNoisyStderrAndBoundsInheritedPipes() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "(sleep 3) & head -c 200000 /dev/zero >&2; printf 'done'"]
        let start = Date()
        let output = try QuotaStore.execute(process, timeout: 0.5)
        XCTAssertEqual(output.status, 0)
        XCTAssertEqual(String(data: output.stdout, encoding: .utf8), "done")
        XCTAssertEqual(output.stderr.count, 200000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
        func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    }

    func testMenuBarOrderRanksByConstraint() {
        let providers = [
            provider("claude", fiveHourPercent: 56),
            provider("codex", fiveHourPercent: 82),
            provider("cursor", fiveHourPercent: 63),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 2).map(\.id),
            ["codex", "cursor"]
        )
    }

    func testMenuBarOrderTieBreaksToEarlierProvider() {
        let providers = [
            provider("codex", fiveHourPercent: 70),
            provider("claude", fiveHourPercent: 70),
            provider("cursor", fiveHourPercent: 50),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 2).map(\.id),
            ["codex", "claude"]
        )
    }

    /// Enabling a provider is an explicit request to see it: a missing
    /// percentage must never remove its ring, only push it to the end.
    func testMenuBarOrderKeepsProvidersWithoutData() {
        let providers = [
            provider("ark", fiveHourPercent: nil),
            provider("claude", fiveHourPercent: nil, weekPercent: 8),
            provider("codex", fiveHourPercent: 2),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 3).map(\.id),
            ["claude", "codex", "ark"]
        )
    }

    /// No-data providers keep their input order among themselves.
    func testMenuBarOrderNoDataProvidersKeepInputOrder() {
        let providers = [
            provider("minimax", fiveHourPercent: nil),
            provider("ark", fiveHourPercent: nil),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 3).map(\.id),
            ["minimax", "ark"]
        )
    }

    /// Score is the worse of the two windows, not whichever field is present.
    func testMenuBarOrderUsesMaxOfBothWindows() {
        let providers = [
            provider("claude", fiveHourPercent: nil, weekPercent: 40),
            provider("codex", fiveHourPercent: 2, weekPercent: 90),
        ]
        XCTAssertEqual(
            QuotaStore.menuBarOrder(in: providers, count: 1).map(\.id),
            ["codex"]
        )
    }

    func testMenuBarOrderBoundsAndEmpty() {
        let providers = [
            provider("codex", fiveHourPercent: 82),
            provider("claude", fiveHourPercent: 56),
        ]
        XCTAssertEqual(QuotaStore.menuBarOrder(in: providers, count: 0), [])
        XCTAssertEqual(QuotaStore.menuBarOrder(in: [], count: 3), [])
        // `count` caps, never pads.
        XCTAssertEqual(QuotaStore.menuBarOrder(in: providers, count: 9).count, 2)
    }
}
