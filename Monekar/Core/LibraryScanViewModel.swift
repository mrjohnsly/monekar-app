import Foundation
import Observation

@MainActor
@Observable
final class LibraryScanViewModel {
    private(set) var status: MonekarAPI.ScanStatus?
    private(set) var report: MonekarAPI.ScanReport?
    private(set) var statusError: String?
    private(set) var rescanError: String?
    private(set) var isRefreshing = false
    private(set) var isRescanning = false
    private var scanMayBeRunning = false
    private let api: any APIService
    private let sleep: () async throws -> Void
    private var observers: Set<UUID> = []
    private var pollingTask: Task<Void, Never>?
    private var pollingID = UUID()
    private var generation = UUID()
    private var sessionID: UUID?
    private var baseURL: URL?
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []

    var canRescan: Bool {
        status != nil && status?.state != .running && statusError == nil
            && !isRefreshing && !isRescanning && !scanMayBeRunning
    }

    init(
        api: any APIService,
        sleep: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(2)) }
    ) {
        self.api = api
        self.sleep = sleep
        sessionID = api.mediaSessionID
        baseURL = api.baseURL
    }

    func synchronizeConnection() {
        guard sessionID != api.mediaSessionID || baseURL != api.baseURL else { return }
        sessionID = api.mediaSessionID
        baseURL = api.baseURL
        generation = UUID()
        stopMonitoring()
        status = nil
        report = nil
        statusError = nil
        rescanError = nil
        isRescanning = false
        scanMayBeRunning = false
        finishRefresh()
        startMonitoring()
    }

    func setActive(_ active: Bool, observer: UUID) {
        synchronizeConnection()
        if active {
            observers.insert(observer)
            startMonitoring()
        } else {
            observers.remove(observer)
            if observers.isEmpty { stopMonitoring() }
        }
    }

    func refresh() async {
        let generation = generation
        while isRefreshing {
            await withCheckedContinuation { refreshWaiters.append($0) }
        }
        guard !Task.isCancelled, generation == self.generation else { return }
        isRefreshing = true
        defer {
            if generation == self.generation { finishRefresh() }
        }
        do {
            let status = try await api.scanStatus()
            try Task.checkCancellation()
            guard generation == self.generation else { return }
            self.status = status
            statusError = nil
            if !isRescanning { scanMayBeRunning = status.state == .running }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, generation == self.generation else { return }
            statusError = Self.message(for: error)
        }
    }

    func refreshStatus() async {
        await refresh()
        startMonitoring(refreshImmediately: false)
    }

    func rescan() async {
        guard canRescan else { return }
        let generation = generation
        isRescanning = true
        scanMayBeRunning = true
        rescanError = nil
        report = nil
        startMonitoring()
        do {
            let report = try await api.rescan()
            guard generation == self.generation else { return }
            self.report = report
        } catch {
            guard generation == self.generation else { return }
            // A cancelled or failed request may still have started a server scan.
            rescanError = Self.message(for: error)
        }
        guard generation == self.generation else { return }
        isRescanning = false
        await refresh()
        startMonitoring(refreshImmediately: false)
    }

    private func startMonitoring(refreshImmediately: Bool = true) {
        guard !observers.isEmpty, pollingTask == nil else { return }
        guard refreshImmediately || status?.state == .running || isRescanning || scanMayBeRunning else { return }
        let id = UUID()
        pollingID = id
        pollingTask = Task { [weak self] in
            guard let self else { return }
            if refreshImmediately { await refresh() }
            while !Task.isCancelled && (status?.state == .running || isRescanning || scanMayBeRunning) {
                do {
                    try await sleep()
                    try Task.checkCancellation()
                } catch { break }
                await refresh()
            }
            if pollingID == id { pollingTask = nil }
        }
    }

    private func stopMonitoring() {
        pollingID = UUID()
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func finishRefresh() {
        isRefreshing = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case ConnectionFailure.serverRejected(409):
            "A library scan is already running (HTTP 409). Status will refresh automatically."
        case ConnectionFailure.serverRejected(503):
            "The library is unavailable (HTTP 503). Check the server library and try again."
        case let failure as ConnectionFailure:
            failure.message
        case is CancellationError:
            "The rescan request was interrupted. Refresh status before trying again."
        default:
            "The request failed. Refresh status and try again."
        }
    }
}
