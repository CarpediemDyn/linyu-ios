import Foundation
import XCTest
@testable import LinYuIOS

@MainActor final class NearbyMeterNameResolverTests: XCTestCase {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    func testUnknownSameNameMetersResolveSeriallyByObservedIdentityAfterScan() async {
        let h = NameResolverFixture()
        let cycle = UUID()
        let done = expectation(description: "Both identities resolved")
        done.expectedFulfillmentCount = 2
        h.didResolve = { done.fulfill() }
        let started = expectation(description: "First connection remains pending")
        let gate = NameIdentityGate()
        let firstID = first
        h.readOverride = { id in
            if id == firstID {
                started.fulfill()
                return try await gate.wait()
            }
            return NameResolverFixture.identity(id)
        }
        let meters = [meter(first, at: h.time), meter(second, at: h.time)]
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: false)
        XCTAssertTrue(h.reads.isEmpty)
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true)
        for _ in 0..<5 { await Task.yield() }
        XCTAssertEqual(h.reads, [first])
        gate.finish(.success(NameResolverFixture.identity(first)))
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(h.reads, [first, second])
        XCTAssertEqual(h.maximumReads, 1)
        XCTAssertEqual(h.resolved[first]?.deviceName, "测试设备 A")
        XCTAssertEqual(h.resolved[second]?.deviceName, "测试设备 B")
        XCTAssertEqual(h.lookups, ["C01122334401", "C01122334402"])
        XCTAssertEqual(h.queue.states[first], .resolved)
        XCTAssertEqual(h.queue.states[second], .resolved)
    }

    func testValidCacheHitDoesNotConnectOrQueryLedger() {
        let h = NameResolverFixture()
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [first], enabled: true)
        XCTAssertTrue(h.reads.isEmpty)
        XCTAssertTrue(h.lookups.isEmpty)
        XCTAssertEqual(h.queue.states[first], .resolved)
        XCTAssertTrue(h.logs.contains { $0.contains("cache_hit=") && $0.contains("display_name_updated=") })
    }

    func testRepeatedDiscoveryCoalescesOneAttemptAndLeavesManualRetryAvailable() async {
        let h = NameResolverFixture()
        let started = expectation(description: "Read started")
        let gate = NameIdentityGate()
        h.readOverride = { _ in started.fulfill(); return try await gate.wait() }
        let failed = expectation(description: "Automatic read failed")
        h.didLog = { if $0.contains("identify_failed=") { failed.fulfill() } }
        let cycle = UUID()
        let meters = [meter(first, at: h.time, rssi: -98)]
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        for _ in 0..<10 { h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true) }
        XCTAssertEqual(h.reads, [first])
        gate.finish(.failure(WaterError.timeout))
        await fulfillment(of: [failed], timeout: 3)
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true)
        XCTAssertEqual(h.reads, [first])
        XCTAssertEqual(h.queue.states[first], .failed)
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertTrue(h.lookups.isEmpty)
    }

    func testExplicitNewScanMayRetryAnEarlierConnectionTimeout() async {
        let h = NameResolverFixture()
        h.readOverride = { _ in throw WaterError.timeout }
        let failed = expectation(description: "Timeout")
        h.didLog = { if $0.contains("identify_failed=") { failed.fulfill() } }
        let meters = [meter(first, at: h.time)]
        h.queue.update(meters, scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [failed], timeout: 3)
        h.didLog = nil
        h.readOverride = nil
        let done = expectation(description: "Explicit retry resolved")
        h.didResolve = { done.fulfill() }
        h.queue.update(meters, scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(h.reads, [first, first])
        XCTAssertEqual(h.queue.states[first], .resolved)
    }

    func testLedgerFailureStopsLoadingAndDiagnosticDoesNotIncludeErrorContents() async {
        let h = NameResolverFixture()
        h.lookupOverride = { _ in throw QzxyError.server("loginCode=private-value device=private-meter") }
        let failed = expectation(description: "Ledger failed")
        h.didLog = { if $0.contains("identify_failed=") { failed.fulfill() } }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(h.queue.states[first], .failed)
        XCTAssertTrue(h.resolved.isEmpty)
        let text = h.logs.joined(separator: " ")
        XCTAssertTrue(text.contains("identity_received="))
        XCTAssertTrue(text.contains("ledger_lookup_started="))
        XCTAssertTrue(text.contains("ledger_lookup_finished="))
        XCTAssertFalse(text.contains("private-value"))
        XCTAssertFalse(text.contains("private-meter"))
        XCTAssertFalse(text.contains("C01122334401"))
    }

    func testMismatchedLedgerCannotNameAnotherPhysicalMeter() async {
        let h = NameResolverFixture()
        h.lookupOverride = { _ in NameResolverFixture.device("C01122334402") }
        let failed = expectation(description: "Mismatch rejected")
        h.didLog = { if $0.contains("identity_mismatch=") { failed.fulfill() } }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertEqual(h.queue.states[first], .failed)
        XCTAssertTrue(h.resolved.isEmpty)
    }

    func testOriginalDerivedMACMappingIsAcceptedWithoutGuessingName() async {
        let h = NameResolverFixture()
        h.lookupOverride = { _ in NameResolverFixture.device("001122334401") }
        let done = expectation(description: "Derived MAC ledger verified")
        h.didResolve = { done.fulfill() }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(h.resolved[first]?.macAddress, "001122334401")
        XCTAssertEqual(h.queue.states[first], .resolved)
    }

    func testExpiredPresenceDuringLedgerRequestDoesNotPublishStaleResult() async {
        let h = NameResolverFixture()
        let gate = NameLedgerGate()
        let started = expectation(description: "Ledger started")
        h.lookupOverride = { _ in started.fulfill(); return await gate.wait() }
        let cancelled = expectation(description: "Stale result suppressed")
        h.didLog = { if $0.contains("cancelled=") { cancelled.fulfill() } }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.time = h.time.addingTimeInterval(61)
        gate.finish(NameResolverFixture.device("C01122334401"))
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertEqual(h.queue.states[first], .failed)
    }

    func testManualPreemptionCancelsBeforeLedgerAndPreventsLateNameUpdate() async {
        let h = NameResolverFixture()
        let gate = NameIdentityGate()
        let started = expectation(description: "Automatic read started")
        h.readOverride = { _ in started.fulfill(); return try await gate.wait() }
        let cancelled = expectation(description: "Cancelled read retired")
        h.didLog = { if $0.contains("cancelled=") { cancelled.fulfill() } }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.queue.pause()
        gate.finish(.success(NameResolverFixture.identity(first)))
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertTrue(h.lookups.isEmpty)
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertEqual(h.queue.states[first], .failed)
    }

    func testLeavingPageDuringLookupSuppressesItsResult() async {
        let h = NameResolverFixture()
        let lookup = NameLedgerGate()
        let started = expectation(description: "Ledger started")
        h.lookupOverride = { _ in started.fulfill(); return await lookup.wait() }
        let cancelled = expectation(description: "Page cancellation")
        h.didLog = { if $0.contains("cancelled=") { cancelled.fulfill() } }
        let cycle = UUID()
        let meters = [meter(first, at: h.time)]
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.queue.update(meters, scanID: cycle, cachedIDs: [], enabled: false)
        lookup.finish(NameResolverFixture.device("C01122334401"))
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertEqual(h.queue.states[first], .failed)
    }

    func testTransactionOrActiveConnectionDefersQueuedDevices() {
        let h = NameResolverFixture()
        h.queue.update([meter(first, at: h.time), meter(second, at: h.time)],
                       scanID: UUID(), cachedIDs: [], enabled: false)
        XCTAssertTrue(h.reads.isEmpty)
        XCTAssertTrue(h.lookups.isEmpty)
        XCTAssertEqual(h.queue.states[first], .queued)
        XCTAssertEqual(h.queue.states[second], .queued)
    }

    func testMissingAndStaleDevicesDoNotReceiveBackgroundConnections() async {
        let h = NameResolverFixture()
        let started = expectation(description: "Read started")
        let gate = NameIdentityGate()
        h.readOverride = { _ in started.fulfill(); return try await gate.wait() }
        let cancelled = expectation(description: "Removed candidate cancelled")
        h.didLog = { if $0.contains("cancelled=") { cancelled.fulfill() } }
        let cycle = UUID()
        h.queue.update([meter(first, at: h.time)], scanID: cycle, cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.queue.update([], scanID: cycle, cachedIDs: [], enabled: true)
        gate.finish(.success(NameResolverFixture.identity(first)))
        await fulfillment(of: [cancelled], timeout: 3)
        h.didLog = nil
        h.queue.update([meter(second, at: h.time.addingTimeInterval(-61))], scanID: UUID(), cachedIDs: [], enabled: true)
        XCTAssertEqual(h.reads, [first])
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertEqual(h.queue.states[second], .failed)
    }

    func testAccountResetIgnoresLateOldOwnerLookup() async {
        let h = NameResolverFixture()
        let gate = NameLedgerGate()
        let started = expectation(description: "Old owner lookup started")
        h.lookupOverride = { _ in started.fulfill(); return await gate.wait() }
        let cancelled = expectation(description: "Old owner result suppressed")
        h.didLog = { if $0.contains("cancelled=") { cancelled.fulfill() } }
        h.queue.update([meter(first, at: h.time)], scanID: UUID(), cachedIDs: [], enabled: true)
        await fulfillment(of: [started], timeout: 3)
        h.queue.reset()
        gate.finish(NameResolverFixture.device("C01122334401"))
        await fulfillment(of: [cancelled], timeout: 3)
        XCTAssertTrue(h.resolved.isEmpty)
        XCTAssertTrue(h.queue.states.isEmpty)
    }

    func testVerifiedCacheSurvivesRestartIsAccountScopedAndRejectsChangedIdentity() throws {
        let suite = "NearbyNames." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let device = NameResolverFixture.device("C01122334401")
        var cache = CampusMeterDisplayCache(ownerScope: "test-owner-A", defaults: defaults)
        cache.store(device, for: first, now: now, observedMAC: "C01122334401")
        let restored = CampusMeterDisplayCache(ownerScope: "test-owner-A", defaults: defaults)
        XCTAssertEqual(restored.device(for: first, now: now.addingTimeInterval(1)), device)
        XCTAssertNil(restored.device(for: first, now: now.addingTimeInterval(86_401)))
        XCTAssertNil(CampusMeterDisplayCache(ownerScope: "test-owner-B", defaults: defaults).device(for: first))
        cache.store(device, for: first, now: now, observedMAC: "C01122334402")
        XCTAssertNil(cache.device(for: first, now: now))
    }

    private func meter(_ id: UUID, at date: Date, rssi: Int = -60) -> DiscoveredWaterMeter {
        DiscoveredWaterMeter(id: id, name: "KLCXKJ Water", rssi: rssi, lastSeen: date)
    }
}

@MainActor private final class NameResolverFixture {
    var time = Date()
    var reads: [UUID] = []
    var lookups: [String] = []
    var resolved: [UUID: CampusDevice] = [:]
    var logs: [String] = []
    var maximumReads = 0
    private var activeReads = 0
    var readOverride: ((UUID) async throws -> WaterMeterIdentity)?
    var lookupOverride: ((String) async throws -> CampusDevice?)?
    var didResolve: (() -> Void)?
    var didLog: ((String) -> Void)?
    lazy var queue = NearbyMeterNameResolver(readIdentity: { [unowned self] id in
        reads.append(id)
        activeReads += 1
        maximumReads = max(maximumReads, activeReads)
        defer { activeReads -= 1 }
        if let readOverride { return try await readOverride(id) }
        return NameResolverFixture.identity(id)
    }, loadDevice: { [unowned self] mac in
        lookups.append(mac)
        if let lookupOverride { return try await lookupOverride(mac) }
        return NameResolverFixture.device(mac)
    }, onResolved: { [unowned self] id, device, _ in
        resolved[id] = device
        didResolve?()
    }, trace: { [unowned self] in
        LatencyTrace("mock_name") { [unowned self] text in logs.append(text); didLog?(text) }
    }, now: { [unowned self] in time })

    static func identity(_ id: UUID) -> WaterMeterIdentity {
        WaterMeterIdentity(projectId: "0", deviceId: "0", accountId: "0",
                           macAddress: id.uuidString.hasSuffix("1") ? "C01122334401" : "C01122334402")
    }
    static func device(_ mac: String) -> CampusDevice {
        CampusDevice(deviceId: mac, deviceName: mac.hasSuffix("1") ? "测试设备 A" : "测试设备 B",
                     snCode: mac, macAddress: mac)
    }
}

@MainActor private final class NameIdentityGate {
    private var continuation: CheckedContinuation<WaterMeterIdentity, Error>?
    func wait() async throws -> WaterMeterIdentity {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ result: Result<WaterMeterIdentity, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

@MainActor private final class NameLedgerGate {
    private var continuation: CheckedContinuation<CampusDevice?, Never>?
    func wait() async -> CampusDevice? { await withCheckedContinuation { continuation = $0 } }
    func finish(_ device: CampusDevice?) {
        continuation?.resume(returning: device)
        continuation = nil
    }
}
