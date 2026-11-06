import Foundation
import Combine

/// One read-only attempt per UUID per scan. The caller supplies a scoped ledger lookup;
/// this type has no valve, order, upload, pairing or settlement capability.
@MainActor final class NearbyMeterNameResolver: ObservableObject {
    enum State: Equatable { case queued, identifying, resolved, failed }
    @Published private(set) var states: [UUID: State] = [:]
    private let readIdentity: @MainActor (UUID) async throws -> WaterMeterIdentity
    private let loadDevice: @MainActor (String) async throws -> CampusDevice?
    private let onResolved: @MainActor (UUID, CampusDevice, String) -> Void
    private let trace: @MainActor () -> LatencyTrace
    private let now: @MainActor () -> Date
    private var candidates: [DiscoveredWaterMeter] = []
    private var cached = Set<UUID>()
    private var attempted = Set<UUID>()
    private var traces: [UUID: LatencyTrace] = [:]
    private var cycle: UUID?
    private var epoch = UUID()
    private var task: Task<Void, Never>?
    private var active: UUID?
    private var enabled = false
    static let freshness: TimeInterval = 60

    init(readIdentity: @escaping @MainActor (UUID) async throws -> WaterMeterIdentity,
         loadDevice: @escaping @MainActor (String) async throws -> CampusDevice?,
         onResolved: @escaping @MainActor (UUID, CampusDevice, String) -> Void,
         trace: @escaping @MainActor () -> LatencyTrace,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.readIdentity = readIdentity
        self.loadDevice = loadDevice
        self.onResolved = onResolved
        self.trace = trace
        self.now = now
    }

    func update(_ meters: [DiscoveredWaterMeter], scanID: UUID, cachedIDs: Set<UUID>, enabled: Bool) {
        if cycle != scanID {
            reset()
            cycle = scanID
        }
        candidates = meters
        cached = cachedIDs
        self.enabled = enabled
        let ids = Set(meters.map(\.id))
        for meter in meters where states[meter.id] == nil {
            let event = trace()
            event.mark("scan_discovered")
            if cachedIDs.contains(meter.id) {
                event.mark("cache_hit")
                event.finish("display_name_updated")
                states[meter.id] = .resolved
            } else {
                event.mark("identify_queued")
                traces[meter.id] = event
                states[meter.id] = .queued
            }
        }
        for id in cachedIDs where states[id] != .resolved {
            if let event = traces.removeValue(forKey: id) {
                event.mark("cache_hit")
                event.finish("display_name_updated")
            }
            states[id] = .resolved
        }
        if let active, !enabled || !ids.contains(active) || !isFresh(active) { cancelActive() }
        pump()
    }

    func pause() {
        enabled = false
        cancelActive()
    }

    private func cancelActive() {
        task?.cancel()
        if let active, states[active] == .identifying { states[active] = .failed }
    }

    func reset() {
        pause()
        epoch = UUID()
        candidates = []
        cached = []
        attempted = []
        states = [:]
        traces = [:]
        cycle = nil
    }

    private func isFresh(_ id: UUID) -> Bool {
        guard let meter = candidates.first(where: { $0.id == id }) else { return false }
        return (0...Self.freshness).contains(now().timeIntervalSince(meter.lastSeen))
    }

    private func pump() {
        guard enabled, task == nil else { return }
        for meter in candidates where !cached.contains(meter.id) && !attempted.contains(meter.id) {
            if !isFresh(meter.id) {
                attempted.insert(meter.id)
                if let event = traces.removeValue(forKey: meter.id) {
                    event.mark("identify_failed")
                    event.finish("stale")
                }
                states[meter.id] = .failed
                continue
            }
            let id = meter.id
            let token = epoch
            let event = traces.removeValue(forKey: id) ?? trace()
            attempted.insert(id)
            active = id
            states[id] = .identifying
            task = Task { [weak self] in
                guard let self else { return }
                defer { self.task = nil; self.active = nil; self.pump() }
                do {
                    try Task.checkCancellation()
                    event.mark("ble_connect_started")
                    let identity = try await self.readIdentity(id)
                    try Task.checkCancellation()
                    guard self.epoch == token, self.enabled, self.isFresh(id) else { throw CancellationError() }
                    event.mark("identity_received")
                    event.mark("ledger_lookup_started")
                    let device: CampusDevice?
                    do {
                        defer { event.mark("ledger_lookup_finished") }
                        device = try await self.loadDevice(identity.macAddress)
                    }
                    try Task.checkCancellation()
                    guard self.epoch == token, self.enabled, self.isFresh(id) else { throw CancellationError() }
                    guard let device else { throw WaterError.invalid("未查到设备台账") }
                    guard device.matchesObservedMAC(identity.macAddress),
                          !device.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw WaterError.identity
                    }
                    self.onResolved(id, device, identity.macAddress)
                    self.states[id] = .resolved
                    event.finish("display_name_updated")
                } catch {
                    event.mark("identify_failed")
                    event.finish(Self.failureCategory(error))
                    if self.epoch == token, !self.cached.contains(id) { self.states[id] = .failed }
                }
            }
            return
        }
    }

    private static func failureCategory(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        if let water = error as? WaterError {
            switch water {
            case .timeout: return "timeout"
            case .identity, .unsupportedIdentity: return "identity_mismatch"
            case .busy: return "busy"
            case .disconnected: return "disconnected"
            default: return "ledger_unavailable"
            }
        }
        return error is URLError ? "network_error" : "ledger_unavailable"
    }
}
