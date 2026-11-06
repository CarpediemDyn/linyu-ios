import Foundation
import XCTest
#if SWIFT_PACKAGE
@testable import LinYuCore
#else
@testable import LinYuIOS
#endif

@MainActor final class WaterTransactionTests: XCTestCase {
    let session = QzxySession(telephone: "13800138000", loginCode: "test-token", userId: "7", accountId: "19381", projectId: "513")
    let meterID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    var device: LedgerDevice { LedgerDevice(deviceId: "2564", snCode: "test-sn", name: "test meter", macAddress: "C47F0E3E4CFD", realMac: nil, bigTypeId: "4", smallTypeId: "1") }

    func make() throws -> (WaterTransactionEngine, TestTransport, TestService, TestJournal) {
        let ble = TestTransport(id: meterID)
        let api = TestService()
        let store = TestJournal()
        let engine = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in Data([1]) })
        return (engine, ble, api, store)
    }

    func testLatencyFixtureForIdentificationAndValveLifecycle() async throws {
        let (engine, ble, api, store) = try make()
        ble.commandDelay = 30_000_000
        ble.reconnectDelay = 100_000_000
        api.rateDelay = 60_000_000
        api.uploadDelay = 150_000_000

        let identify = LatencyTrace("mock_identify", report: { print($0) })
        identify.mark("tap")
        try await ble.connectForTransaction(to: meterID)
        identify.mark("ble_ready")
        let proof = try await engine.readAssociation()
        identify.mark("state_received")
        try await Task.sleep(nanoseconds: 80_000_000)
        identify.mark("ledger_received")
        let binding = try await engine.pair(device: device, session: session, observation: proof)
        identify.finish("detail_ready")
        XCTAssertEqual(ble.commands, [0x23])

        let open = LatencyTrace("mock_ble_open", report: { print($0) })
        open.mark("tap")
        try await engine.open(binding: binding, session: session, trace: open)
        open.finish("shower_ready")
        XCTAssertFalse(ble.reconnected)
        XCTAssertEqual(ble.commands, [0x23, 0x23, 0x21])

        let tx = try XCTUnwrap(engine.journal.transactions.last)
        let close = LatencyTrace("mock_ble_close", report: { print($0) })
        close.mark("confirmed_tap")
        var confirmedBeforeSettlement = false
        close.onStage = { stage in
            guard stage == "closed_saved" else { return }
            XCTAssertEqual(store.snapshot.transactions.last?.valve, .closed)
            XCTAssertNil(store.snapshot.transactions.last?.receipt)
            XCTAssertEqual(api.uploadCalls, 0)
            confirmedBeforeSettlement = true
            close.onStage = nil
            close.mark("closing_indicator_ended")
        }
        try await engine.closeAndSettle(id: tx.id, session: session, trace: close)
        close.finish("settled")
        XCTAssertTrue(confirmedBeforeSettlement)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .completed)
    }

    func testAssociationRejectsAnObservationFromAnotherConnection() async throws {
        let (engine, ble, _, _) = try make()
        let proof = try await engine.readAssociation()
        try await ble.reconnectForTransaction(to: meterID)
        do {
            _ = try await engine.pair(device: device, session: session, observation: proof)
            XCTFail("An observation survived a connection change")
        } catch WaterError.identity {}
        XCTAssertTrue(engine.journal.bindings.isEmpty)
    }

    func testClosedACKPersistsAcrossRelaunchBeforeCollection() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let tx = try XCTUnwrap(engine.journal.transactions.last)
        ble.failCommand = 0x85
        do { try await engine.closeAndSettle(id: tx.id, session: session); XCTFail("Collection should fail") } catch WaterError.timeout {}
        XCTAssertEqual(store.snapshot.transactions.last?.valve, .closed)

        ble.failCommand = nil
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in Data([1]) })
        try await restored.recover(id: tx.id, session: session)
        XCTAssertEqual(ble.commands.filter { $0 == 0x22 }.count, 1)
        XCTAssertTrue(ble.reconnectedBeforeCollect)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(store.snapshot.transactions.last?.phase, .completed)
    }

    func testShortFrameIdentityUsesCommonSelfReportedPrefix() throws {
        let state = try XCTUnwrap(BleDeviceState.parse(Data(hex: "800000020100000A0400004BB5C47F0E3E4CFD000000000001000000")!))
        XCTAssertEqual(state.identity?.projectId, "513")
        XCTAssertEqual(state.identity?.deviceId, "2564")
        XCTAssertEqual(state.identity?.accountId, "19381")
        XCTAssertEqual(state.identity?.macAddress, "C47F0E3E4CFD")
    }

    func testLongStateLayoutsUseCommonPrefixAndOriginalOffsets() async throws {
        for length in [31, 48, 63, 80] {
            let (engine, ble, _, _) = try make()
            ble.stateLength = length
            let binding = try await engine.pair(device: device, session: session)
            XCTAssertEqual(binding.observedMAC, "C47F0E3E4CFD")
            try await engine.open(binding: binding, session: session)
            XCTAssertEqual(engine.journal.transactions.last?.protocolType, "02")
            XCTAssertEqual(engine.journal.transactions.last?.randomNumber, "01020304")
            XCTAssertEqual(engine.journal.transactions.last?.phase, .running)
        }
    }

    func testSelfReportedProjectDeviceAndAccountAreNotAuthentication() async throws {
        let (engine, ble, api, _) = try make()
        ble.project = 999; ble.device = 42; ble.stateAccount = 1
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(api.rateCalls, 1)
    }

    func testMACRoutingRejectsAnotherMeter() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        ble.mac = [0, 1, 2, 3, 4, 5]
        do { try await engine.open(binding: binding, session: session); XCTFail("different meter") } catch {}
        XCTAssertEqual(api.rateCalls, 0)
        XCTAssertFalse(ble.commands.contains(0x21))
    }

    func testStorageFailurePreventsOpeningSideEffect() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        store.fail = true
        do { try await engine.open(binding: binding, session: session); XCTFail("storage failure") } catch {}
        XCTAssertEqual(api.rateCalls, 0)
        XCTAssertFalse(ble.commands.contains(0x21))
    }

    func testOpeningIntentIsSavedBeforeWrite() async throws {
        let (engine, ble, _, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        ble.onOpening = { XCTAssertEqual(store.snapshot.transactions.last?.phase, .opening) }
        ble.failCommand = 0x21
        do { try await engine.open(binding: binding, session: session); XCTFail("lost ACK") } catch {}
        XCTAssertEqual(engine.journal.transactions.last?.valve, .unknown)
    }

    func testOpenACKIsEnoughWithoutMandatoryStatusOneQuery() async throws {
        let (engine, ble, _, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        ble.failQueryAfterOpening = true
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .running)
        XCTAssertEqual(ble.commands.last, 0x21)
    }

    func testEmptyConsumeDateDoesNotRejectValidGrant() async throws {
        let (engine, _, api, _) = try make()
        api.consumeDate = ""
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .running)
        XCTAssertEqual(engine.journal.transactions.last?.consumeDate, "")
    }

    func testIdleReconnectAllowsRetryAfterUnconfirmedOpen() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        ble.failCommand = 0x21
        do { try await engine.open(binding: binding, session: session); XCTFail("lost ACK") } catch {}
        ble.failCommand = nil
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(api.rateCalls, 2)
        XCTAssertEqual(engine.journal.transactions.first?.phase, .needsAttention)
        XCTAssertEqual(engine.journal.transactions.first?.orderNo, "test-order")
        XCTAssertEqual(engine.journal.transactions.first?.usageState, .settlementPending)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .running)
    }

    func testRunningLocalOrderResumesWithoutAnotherRateOrOpen() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last?.id
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(api.rateCalls, 1)
        XCTAssertEqual(ble.commands.filter { $0 == 0x21 }.count, 1)
        XCTAssertEqual(engine.journal.transactions.last?.id, id)
    }

    func testRunningMeterWithoutLocalActiveOrderCannotBeAdopted() async throws {
        let (engine, ble, api, _) = try make()
        ble.state = 1
        let binding = try await engine.pair(device: device, session: session)
        do { try await engine.open(binding: binding, session: session); XCTFail("someone is using meter") } catch {}
        do { _ = try await engine.adoptPending(binding: binding, session: session); XCTFail("no local order") } catch {}
        XCTAssertEqual(api.rateCalls, 0)
        XCTAssertTrue(engine.journal.transactions.isEmpty)
    }

    func testPendingThreeAndSixAutoSettleThenRequireFreshStart() async throws {
        for pendingState in [UInt8(3), UInt8(6)] {
            let (engine, ble, api, _) = try make()
            let binding = try await engine.pair(device: device, session: session)
            ble.state = pendingState
            do {
                try await engine.open(binding: binding, session: session)
                XCTFail("must request a new user start")
            } catch WaterError.recovered(let message) { XCTAssertTrue(message.contains("重新")) }
            XCTAssertEqual(api.rateCalls, 0)
            XCTAssertEqual(api.uploadCalls, 1)
            XCTAssertFalse(ble.commands.contains(0x21))
            XCTAssertEqual(engine.journal.transactions.last?.phase, .completed)
            XCTAssertGreaterThan(ble.disconnectCalls, 0)
            try await engine.open(binding: binding, session: session)
            XCTAssertEqual(api.rateCalls, 1)
        }
    }

    func testIndependentDevicesMayHaveActiveOrdersAndRestore() async throws {
        let (engine, ble, api, store) = try make()
        let first = try await engine.pair(device: device, session: session)
        try await engine.open(binding: first, session: session)
        ble.peripheralID = UUID(); ble.state = 0; ble.mac = [0xC0, 1, 2, 3, 4, 5]
        let other = LedgerDevice(deviceId: "99", snCode: "other-meter", name: "other", macAddress: "000102030405", realMac: nil, bigTypeId: "0", smallTypeId: "0")
        let second = try await engine.pair(device: other, session: session)
        try await engine.open(binding: second, session: session)
        XCTAssertEqual(engine.journal.transactions.filter(\.isPending).count, 2)
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in Data([1]) })
        XCTAssertEqual(restored.journal.transactions.filter(\.isPending).count, 2)
        XCTAssertEqual(api.rateCalls, 2)
    }

    func testSuccessfulCloseReconnectsBeforeCollecting() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: session)
        let record = try XCTUnwrap(engine.journal.transactions.last)
        XCTAssertEqual(record.valve, .closed)
        XCTAssertEqual(record.phase, .completed)
        XCTAssertNotNil(record.receipt)
        XCTAssertTrue(record.writeBackAcknowledged)
        XCTAssertFalse(record.idleConfirmed) // no mandatory final query in the original
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertTrue(ble.reconnectedBeforeCollect)
        XCTAssertEqual(ble.commands.last, 0x86)
    }

    func testConsumptionIsOpaqueAndSupportsExtendedRecords() async throws {
        for length in [42, 63, 80] {
            let (engine, ble, api, _) = try make()
            let binding = try await engine.pair(device: device, session: session)
            try await engine.open(binding: binding, session: session)
            ble.consumptionLength = length; ble.consumptionAccount = 999
            try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: session)
            XCTAssertEqual(api.uploaded?.count, length)
            XCTAssertEqual(api.uploaded, ble.lastConsumption)
            XCTAssertEqual(engine.journal.transactions.last?.phase, .completed)
        }
    }

    func testTruncatedOrFailedConsumptionIsNotUploadedAndReportsFailure() async throws {
        for invalid in [Data(), Data([0x80]), Data(repeating: 0x80, count: 41), Data(repeating: 0, count: 63)] {
            let (engine, ble, api, _) = try make()
            let binding = try await engine.pair(device: device, session: session)
            try await engine.open(binding: binding, session: session)
            ble.consumptionOverride = invalid
            do { try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: session); XCTFail("invalid body") } catch {}
            XCTAssertEqual(api.uploadCalls, 0)
            XCTAssertEqual(api.failureCalls, 1)
            XCTAssertEqual(engine.journal.transactions.last?.valve, .closed)
        }
    }

    func testUploadTimeoutRemainsReadOnlyAcrossRelaunchAndRepeatedRecovery() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        api.failUpload = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("upload timed out") } catch WaterError.disconnected {}
        let closed = try XCTUnwrap(store.snapshot.transactions.last)
        XCTAssertEqual(closed.phase, .uploadUnknown)
        XCTAssertEqual(closed.valve, .closed)
        XCTAssertEqual(closed.usageState, .settlementPending)
        XCTAssertTrue(closed.isPending)
        XCTAssertEqual(api.failureCalls, 0)

        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in Data([1]) })
        api.failUpload = false
        let commandCount = ble.commands.count
        for _ in 0..<2 {
            do { try await restored.recover(id: id, session: session); XCTFail("missing bill") } catch {}
        }
        XCTAssertEqual(ble.commands.count, commandCount)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(api.billChecks, 2)
        XCTAssertEqual(restored.journal.transactions.last?.consumption, closed.consumption)

        api.recordedConsumption = true
        ble.state = 0
        try await restored.recover(id: id, session: session)
        XCTAssertEqual(restored.journal.transactions.last?.usageState, .archived)
        XCTAssertEqual(restored.journal.transactions.last?.billConfirmed, true)
        XCTAssertNil(restored.journal.transactions.last?.receipt)
        XCTAssertEqual(api.uploadCalls, 1)
        _ = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
    }

    func testLegacyUploadUnknownDoesNotProvePhysicalClosure() throws {
        let (_, ble, api, store) = try make()
        let binding = MeterBinding(peripheralID: try XCTUnwrap(ble.peripheralID), ownerScope: session.ownerScope,
                                   device: device, observedMAC: device.apiMAC, verifiedAt: Date())
        let tx = WaterTransaction(id: UUID(), binding: binding, phase: .uploadUnknown, valve: .closed,
                                  protocolType: "1", randomNumber: "", consumeDate: "261104120000",
                                  orderNo: "historical", consumption: Data([0x80]), receipt: nil,
                                  writeBack: nil, failureReportPending: false, lastError: nil, updatedAt: Date())
        try store.save(WaterJournal(transactions: [tx]))
        let engine = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        let restored = try XCTUnwrap(engine.journal.transactions.first)
        XCTAssertEqual(restored.valve, .unknown)
        XCTAssertEqual(restored.usageState, .unconfirmed)
        XCTAssertEqual(restored.consumption, tx.consumption)
    }

    func testLegacySupersededChargeWithSavedConsumptionIsNeverReplayed() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        let payload = Data([0x80]) + Data(repeating: 0xA7, count: 41)
        let tx = WaterTransaction(id: UUID(), binding: binding, phase: .superseded, valve: .closed,
            protocolType: "1", randomNumber: "", consumeDate: "261104120000", orderNo: "superseded",
            consumption: payload, receipt: nil, writeBack: nil, failureReportPending: false,
            lastError: nil, updatedAt: Date())
        try store.save(WaterJournal(transactions: [tx]))
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        ble.state = 3
        ble.consumptionOverride = payload
        let before = ble.commands.count
        do { try await restored.recover(id: tx.id, session: session); XCTFail("no bill confirmation") }
        catch WaterError.invalid {}
        XCTAssertEqual(Array(ble.commands.dropFirst(before)), [0x23])
        XCTAssertEqual(api.uploadCalls, 0)
        XCTAssertEqual(api.billChecks, 1)
        XCTAssertEqual(restored.journal.transactions.last?.phase, .uploadUnknown)
        XCTAssertEqual(restored.journal.transactions.last?.consumption, payload)
    }

    func testLegacyCloseOnlyRecordCannotStopAnotherRunningSession() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        var legacy = try XCTUnwrap(engine.journal.transactions.last)
        legacy.valve = .closed // A legacy close-only operation did not advance the running phase.
        try store.save(WaterJournal(transactions: [legacy]))
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        do { try await restored.recover(id: legacy.id, session: session); XCTFail("another running session") }
        catch WaterError.reconciliation {}
        XCTAssertEqual(restored.journal.transactions.last?.usageState, .unconfirmed)
        XCTAssertFalse(ble.commands.contains(0x22))
        XCTAssertEqual(api.uploadCalls, 0)
    }

    func testRateOnlyRecordCannotCloseAnotherRunningSession() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        let tx = WaterTransaction(id: UUID(), binding: binding, phase: .rateReady, valve: .unknown,
            protocolType: "1", randomNumber: "", consumeDate: "261104120000", orderNo: "rate-only",
            consumption: nil, receipt: nil, writeBack: nil, failureReportPending: false,
            lastError: nil, updatedAt: Date())
        try store.save(WaterJournal(transactions: [tx]))
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        ble.state = 1
        do { try await restored.recover(id: tx.id, session: session); XCTFail("the app never attempted opening") }
        catch WaterError.reconciliation {}
        XCTAssertFalse(ble.commands.contains(0x22))
        XCTAssertEqual(api.uploadCalls, 0)
    }

    func testAnotherAccountCannotAdoptAnAmbiguousChargeFromTheSameMeter() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        api.failUpload = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("upload timed out") }
        catch WaterError.disconnected {}

        api.failUpload = false
        let other = QzxySession(telephone: "13900139000", loginCode: "another", userId: "8",
                                accountId: "1", projectId: "513")
        let otherBinding = try await engine.pair(device: device, session: other)
        let before = ble.commands.count
        do { try await engine.open(binding: otherBinding, session: other); XCTFail("another account owns the record") }
        catch WaterError.reconciliation {}
        do { _ = try await engine.adoptPending(binding: otherBinding, session: other); XCTFail("cannot adopt it") }
        catch WaterError.reconciliation {}
        XCTAssertEqual(Array(ble.commands.dropFirst(before)), [0x23, 0x23])
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(engine.journal.transactions.map(\.id), [id])
    }

    func testOlderRunningRecordCannotCollectFromNewerAccountUsage() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let stale = try XCTUnwrap(engine.journal.transactions.last)
        // The device was closed outside this app, leaving A's journal stale.
        ble.state = 0
        let other = QzxySession(telephone: "13900139000", loginCode: "another", userId: "8",
                                accountId: "1", projectId: "513")
        let otherBinding = try await engine.pair(device: device, session: other)
        try await engine.open(binding: otherBinding, session: other)
        let current = try XCTUnwrap(engine.journal.transactions.last)
        api.failUpload = true
        do { try await engine.closeAndSettle(id: current.id, session: other); XCTFail("upload timed out") }
        catch WaterError.disconnected {}

        api.failUpload = false
        let before = ble.commands
        do { try await engine.recover(id: stale.id, session: session); XCTFail("newer account owns the record") }
        catch WaterError.reconciliation {}
        XCTAssertEqual(ble.commands, before)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .uploadUnknown)
    }

    func testLostUploadResponseChecksAccountBeforeAttemptingBluetooth() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        api.failUpload = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("upload timed out") } catch WaterError.disconnected {}
        api.recordedConsumption = true
        ble.availableForRecovery = false
        let before = ble.commands
        do { try await engine.recover(id: id, session: session); XCTFail("meter write-back needs Bluetooth") }
        catch WaterError.invalid(let guidance) { XCTAssertEqual(guidance, WaterError.meterRecoveryGuidance) }
        XCTAssertEqual(ble.commands, before)
        XCTAssertEqual(engine.journal.transactions.last?.billConfirmed, true)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertFalse(engine.busy)
    }

    func testCloseACKFreezesDurationBeforeReconnectAndSurvivesRelaunch() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        ble.failQueryAfterClose = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("reconnect status should fail") }
        catch WaterError.timeout {}
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        let tx = try XCTUnwrap(restored.journal.transactions.first)
        let stop = try XCTUnwrap(tx.closureConfirmedAt)
        XCTAssertEqual(tx.closureEvidence, .closeAcknowledgement)
        XCTAssertEqual(tx.usageState, .settlementPending)
        XCTAssertNotNil(tx.usageSeconds(at: stop))
        XCTAssertEqual(tx.usageSeconds(at: stop.addingTimeInterval(1141 * 60)), tx.usageSeconds(at: stop))
        XCTAssertTrue(tx.lastError?.contains("0x23") == true)
        XCTAssertFalse(restored.busy)
    }

    func testLegacyOrdersOnDifferentMetersStayIsolatedWhileCheckingBillsOffline() async throws {
        let (_, ble, api, store) = try make()
        let first = MeterBinding(peripheralID: UUID(), ownerScope: session.ownerScope,
                                 device: device, observedMAC: device.apiMAC, verifiedAt: Date())
        let otherDevice = LedgerDevice(deviceId: "447", snCode: "447", name: "D7 447", macAddress: "C47F0E3E4C11",
                                       realMac: nil, bigTypeId: "4", smallTypeId: "1")
        let second = MeterBinding(peripheralID: UUID(), ownerScope: session.ownerScope,
                                  device: otherDevice, observedMAC: otherDevice.apiMAC, verifiedAt: Date())
        let startedAt = Date(timeIntervalSince1970: 100)
        let firstTx = WaterTransaction(id: UUID(), binding: first, phase: .uploadUnknown, valve: .closed,
            protocolType: "1", randomNumber: "", consumeDate: "261104120000", orderNo: "450",
            consumption: Data([0x80]), receipt: nil, writeBack: nil, failureReportPending: false,
            lastError: nil, updatedAt: startedAt, startedAt: startedAt)
        let secondTx = WaterTransaction(id: UUID(), binding: second, phase: .uploading, valve: .closed,
            protocolType: "1", randomNumber: "", consumeDate: "261104120100", orderNo: "447",
            consumption: Data([0x80, 1]), receipt: nil, writeBack: nil, failureReportPending: false,
            lastError: nil, updatedAt: startedAt, startedAt: startedAt)
        try store.save(WaterJournal(transactions: [firstTx, secondTx]))
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        ble.availableForRecovery = false
        api.recordedOrders = ["450"]
        for id in [firstTx.id, secondTx.id, firstTx.id] {
            do { try await restored.recover(id: id, session: session); XCTFail("no meter to reconcile") }
            catch WaterError.invalid {}
        }
        let records = restored.journal.transactions
        XCTAssertEqual(records.map(\.orderNo), ["450", "447"])
        XCTAssertEqual(records.map(\.phase), [.uploadUnknown, .uploadUnknown])
        XCTAssertEqual(records.map(\.valve), [.unknown, .unknown])
        XCTAssertEqual(records.map(\.billConfirmed), [true, nil])
        XCTAssertEqual(records.map { $0.usageSeconds(at: .now) }, [nil, nil])
        XCTAssertEqual(records.map(\.consumption), [firstTx.consumption, secondTx.consumption])
        XCTAssertEqual(api.checkedOrders, ["450", "447"])
        XCTAssertEqual(api.uploadCalls, 0)
        XCTAssertTrue(ble.commands.isEmpty)
        XCTAssertFalse(restored.busy)
    }

    func testOldReceiptDoesNotWriteBackIfTheMeterContainsAnotherRecord() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        ble.failCommand = 0x86
        try await engine.closeAndSettle(id: id, session: session)
        let original = try XCTUnwrap(engine.journal.transactions.last?.consumption)
        ble.failCommand = nil
        ble.consumptionOverride = original + Data([1])
        let before = ble.commands.count
        do { try await engine.recover(id: id, session: session); XCTFail("another record") } catch WaterError.reconciliation {}
        XCTAssertEqual(Array(ble.commands.dropFirst(before)), [0x23, 0x85])
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(engine.journal.transactions.last?.consumption, original)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .writeBackPending)
    }

    func testIdleOpenPreservesAmbiguousSettlementWithoutReusingIt() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = try XCTUnwrap(engine.journal.transactions.last?.id)
        api.failUpload = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("upload timed out") } catch WaterError.disconnected {}
        let pending = try XCTUnwrap(engine.journal.transactions.last)
        ble.state = 0
        try await engine.open(binding: binding, session: session)
        let old = try XCTUnwrap(engine.journal.transactions.first)
        XCTAssertEqual(old.phase, .uploadUnknown)
        XCTAssertEqual(old.consumeDate, pending.consumeDate)
        XCTAssertEqual(old.orderNo, pending.orderNo)
        XCTAssertEqual(old.consumption, pending.consumption)
        XCTAssertTrue(old.idleConfirmed)
        XCTAssertEqual(old.usageState, .settlementPending)
        XCTAssertEqual(engine.journal.transactions.last?.usageState, .running)
        XCTAssertNotEqual(engine.journal.transactions.last?.id, old.id)
    }

    func testOpeningWithPreviousRunningRecordAndStateSixMarksClosedBeforeUpload() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        ble.state = 6
        api.failUpload = true
        do { try await engine.open(binding: binding, session: session); XCTFail("upload timed out") } catch WaterError.disconnected {}
        XCTAssertEqual(engine.journal.transactions.last?.valve, .closed)
        XCTAssertEqual(engine.journal.transactions.last?.usageState, .settlementPending)
        XCTAssertEqual(api.rateCalls, 1)
        XCTAssertFalse(ble.commands.contains(0x22))
    }

    func testReceiptSurvivesFailedWriteBackAndRetryDoesNotUploadAgain() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        ble.failCommand = 0x86
        try await engine.closeAndSettle(id: id, session: session)
        XCTAssertNotNil(store.snapshot.transactions.last?.receipt)
        XCTAssertEqual(store.snapshot.transactions.last?.phase, .writeBackPending)
        XCTAssertEqual(api.failureCalls, 0)
        ble.failCommand = nil
        let restored = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in Data([1]) })
        try await restored.recover(id: id, session: session)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(restored.journal.transactions.last?.phase, .completed)
    }

    func testBadWriteBackDataPreservesAcceptedAccountingAsPartial() async throws {
        let (_, ble, api, store) = try make()
        let engine = try WaterTransactionEngine(transport: ble, service: api, store: store, decodeWriteBack: { _ in nil })
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        try await engine.closeAndSettle(id: id, session: session)
        try await engine.recover(id: id, session: session)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertNotNil(engine.journal.transactions.last?.receipt)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .writeBackPending)
        XCTAssertFalse(ble.commands.contains(0x86))
    }

    func testIdleRecoveryDoesNotInventLostWriteBackACK() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        ble.loseWriteBackACK = true
        try await engine.closeAndSettle(id: id, session: session)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .writeBackPending)
        try await engine.recover(id: id, session: session)
        XCTAssertEqual(api.uploadCalls, 1)
        XCTAssertEqual(engine.journal.transactions.last?.phase, .completed)
        XCTAssertTrue(engine.journal.transactions.last!.idleConfirmed)
        XCTAssertFalse(engine.journal.transactions.last!.writeBackAcknowledged)
    }

    func testDifferentLocalSessionCannotControlOriginalTransaction() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let other = QzxySession(telephone: "13900139000", loginCode: "another", userId: "8", accountId: "1", projectId: "513")
        do { try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: other); XCTFail("wrong local session") } catch {}
        XCTAssertFalse(ble.commands.contains(0x22))
        XCTAssertEqual(api.uploadCalls, 0)
    }

    func testCloseACKFailureReportsWithoutClaimingClosedOrUploading() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        ble.failCommand = 0x22
        do { try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: session); XCTFail("lost ACK") } catch {}
        XCTAssertEqual(engine.journal.transactions.last?.valve, .unknown)
        XCTAssertEqual(engine.journal.transactions.last?.usageState, .unconfirmed)
        XCTAssertEqual(api.uploadCalls, 0)
        XCTAssertEqual(api.failureCalls, 1)
    }

    func testFailedFailureReportRemainsRetryable() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        ble.failCommand = 0x22; api.failReport = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("lost ACK") } catch {}
        XCTAssertTrue(engine.journal.transactions.last!.failureReportPending)
        api.failReport = false
        try await engine.retryFailureReport(id: id, session: session)
        XCTAssertFalse(engine.journal.transactions.last!.failureReportPending)
    }

    func testNoFailureReportWithoutConsumeDate() async throws {
        let (engine, ble, api, _) = try make()
        api.consumeDate = ""
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        ble.failCommand = 0x22
        do { try await engine.closeAndSettle(id: engine.journal.transactions.last!.id, session: session); XCTFail("lost ACK") } catch {}
        XCTAssertEqual(api.failureCalls, 0)
    }

    func testStorageFailureStillAllowsEmergencyClose() async throws {
        let (engine, ble, api, store) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        store.fail = true
        do { try await engine.closeAndSettle(id: id, session: session); XCTFail("storage failure") } catch {}
        try await engine.closeValveOnly(id: id, session: session)
        XCTAssertTrue(ble.commands.contains(0x22))
        XCTAssertEqual(engine.journal.transactions.last?.valve, .closed)
        XCTAssertEqual(api.uploadCalls, 0)
    }

    func testReconnectDuringRateRequestDoesNotWriteStaleGrant() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        api.onRate = { ble.connectionID = UUID() }
        do { try await engine.open(binding: binding, session: session); XCTFail("stale challenge") } catch {}
        XCTAssertFalse(ble.commands.contains(0x21))
    }

    func testServerRateRejectionAllowsNextAttempt() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        api.rejectRate = true
        do { try await engine.open(binding: binding, session: session); XCTFail("rate rejected") } catch {}
        XCTAssertEqual(engine.journal.transactions.last?.phase, .rateRejected)
        XCTAssertFalse(ble.commands.contains(0x21))
        api.rejectRate = false
        try await engine.open(binding: binding, session: session)
        XCTAssertEqual(api.rateCalls, 2)
    }

    func testRecordedReceiptCannotCloseSubsequentRunningUsage() async throws {
        let (engine, ble, api, _) = try make()
        let binding = try await engine.pair(device: device, session: session)
        try await engine.open(binding: binding, session: session)
        let id = engine.journal.transactions.last!.id
        ble.failCommand = 0x86
        try await engine.closeAndSettle(id: id, session: session)
        ble.failCommand = nil; ble.state = 1
        let before = ble.commands.count
        do { try await engine.recover(id: id, session: session); XCTFail("different usage") } catch {}
        XCTAssertFalse(ble.commands.dropFirst(before).contains(0x22))
        XCTAssertFalse(ble.commands.dropFirst(before).contains(0x86))
        XCTAssertEqual(api.uploadCalls, 1)
    }
}

@MainActor final class TestJournal: WaterJournalStore {
    var snapshot = WaterJournal()
    var fail = false
    func load() throws -> WaterJournal { snapshot }
    func save(_ journal: WaterJournal) throws {
        if fail { throw WaterError.storage }
        snapshot = try JSONDecoder().decode(WaterJournal.self, from: JSONEncoder().encode(journal))
    }
}

@MainActor final class TestService: WaterMeterService {
    var rateDelay: UInt64 = 0
    var uploadDelay: UInt64 = 0
    var rateCalls = 0
    var uploadCalls = 0
    var failureCalls = 0
    var failUpload = false
    var billChecks = 0
    var recordedConsumption = false
    var recordedOrders: Set<String> = []
    var checkedOrders: [String] = []
    var failReport = false
    var rejectRate = false
    var consumeDate = "261104120000"
    var uploaded: Data?
    var onRate: (() -> Void)?
    func grantRate(device: LedgerDevice, state: BleDeviceState, session: QzxySession) async throws -> RateGrant {
        rateCalls += 1
        if rateDelay > 0 { try await Task.sleep(nanoseconds: rateDelay) }
        if rejectRate { throw WaterError.rejected("insufficient balance") }
        onRate?()
        return RateGrant(downData: Data([0x10]), consumeDate: consumeDate, orderNo: "test-order")
    }
    func uploadConsumption(_ payload: Data, state: BleDeviceState, session: QzxySession) async throws -> SettlementReceipt {
        uploadCalls += 1; uploaded = payload
        if uploadDelay > 0 { try await Task.sleep(nanoseconds: uploadDelay) }
        if failUpload { throw WaterError.disconnected }
        return SettlementReceipt(clData: "test-cipher", amountRaw: "123")
    }
    func hasRecordedConsumption(_ transaction: WaterTransaction, session: QzxySession) async throws -> Bool {
        billChecks += 1
        checkedOrders.append(transaction.orderNo)
        return recordedConsumption || recordedOrders.contains(transaction.orderNo)
    }
    func reportFailure(consumeDate: String, session: QzxySession) async throws {
        failureCalls += 1
        if failReport { throw WaterError.disconnected }
    }
}

@MainActor final class TestTransport: WaterMeterTransport {
    var peripheralID: UUID?
    var connectionID = UUID()
    var project: UInt32 = 513
    var device: UInt32 = 2564
    var stateAccount: UInt32 = 19381
    var consumptionAccount: UInt32 = 19381
    var state: UInt8 = 0
    var stateLength = 28
    var consumptionLength = 42
    var mac: [UInt8] = [0xC4, 0x7F, 0x0E, 0x3E, 0x4C, 0xFD]
    var consumptionOverride: Data?
    var lastConsumption: Data?
    var failCommand: UInt8?
    var commandDelay: UInt64 = 0
    var reconnectDelay: UInt64 = 0
    var availableForRecovery = true
    var commands: [UInt8] = []
    var onOpening: (() -> Void)?
    var reconnected = false
    var opened = false
    var failQueryAfterOpening = false
    var failQueryAfterClose = false
    var loseWriteBackACK = false
    var reconnectedBeforeCollect = false
    var disconnectCalls = 0
    init(id: UUID) { peripheralID = id }
    func isAvailableForRecovery(_ id: UUID) -> Bool { availableForRecovery }
    func connectForTransaction(to id: UUID) async throws { peripheralID = id }
    func reconnectForTransaction(to id: UUID) async throws {
        if reconnectDelay > 0 { try await Task.sleep(nanoseconds: reconnectDelay) }
        peripheralID = id; connectionID = UUID(); reconnected = true
    }
    func disconnect() { disconnectCalls += 1 }
    func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        for i in 0..<4 { bytes[offset + i] = UInt8((value >> (24 - i * 8)) & 255) }
    }
    func exchange(_ command: UInt8, payload: Data) async throws -> Data {
        commands.append(command)
        if commandDelay > 0 { try await Task.sleep(nanoseconds: commandDelay) }
        if command == 0x21 { onOpening?() }
        if command == 0x86 && loseWriteBackACK {
            loseWriteBackACK = false; state = 0
            throw WaterError.timeout
        }
        if command == failCommand { throw WaterError.timeout }
        if command == 0x21 { state = 1; opened = true }
        if command == 0x22 { state = 3; reconnected = false }
        if command == 0x86 { state = 0 }
        if command == 0x23 {
            if (opened && failQueryAfterOpening) || (state == 3 && failQueryAfterClose) { throw WaterError.timeout }
            var b = [UInt8](repeating: 0, count: stateLength)
            b[0] = 0x80; put(project, into: &b, at: 1); put(device, into: &b, at: 5)
            put(stateAccount, into: &b, at: 9)
            b.replaceSubrange(13..<19, with: mac)
            if stateLength == 28 {
                b[19] = state; b[21] = 1; b[22] = 2; b[23] = 1; b[24] = 1
            } else {
                b[19] = 2; b.replaceSubrange(24..<28, with: [1, 2, 3, 4]); b[28] = state; b[29] = 1; b[30] = 1
            }
            return Data(b)
        }
        if command == 0x85 {
            reconnectedBeforeCollect = reconnected
            if let consumptionOverride { lastConsumption = consumptionOverride; return consumptionOverride }
            var b = [UInt8](repeating: 0xA7, count: consumptionLength)
            b[0] = 0x80; put(project, into: &b, at: 7); put(device, into: &b, at: 11)
            put(consumptionAccount, into: &b, at: 15)
            b.replaceSubrange(36..<42, with: mac)
            lastConsumption = Data(b)
            return Data(b)
        }
        return Data([0x80])
    }
}
