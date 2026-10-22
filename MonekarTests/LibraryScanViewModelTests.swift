import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import MonekarCore
#else
@testable import Monekar
#endif

@MainActor
struct LibraryScanViewModelTests {
    @Test func progressAndReportArePresentedWithoutLosingServerStatus() async throws {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        #expect(!model.canRescan)
        await model.refreshStatus()
        #expect(model.canRescan)
        api.onRescan = {
            #expect(model.isRescanning)
            #expect(!model.canRescan)
            await model.rescan()
        }
        await model.rescan()
        let report = try #require(model.report)
        #expect(report.people == 1)
        #expect(report.albums == 2)
        #expect(report.images == 3)
        #expect(report.ignoredFiles == 4)
        #expect(report.removedImages == 5)
        #expect(report.pruned)
        #expect(report.issues.map(\.reason) == ["Unreadable entry"])
        #expect(api.posts == 1)
        #expect(model.status == api.status)
        #expect(model.canRescan)
    }

    @Test func runningScanBlocksSubmissionsAndRetainsEveryProgressField() async {
        let api = ScanAPI()
        api.status = Self.running
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        await model.rescan()
        #expect(api.posts == 0)
        #expect(!model.canRescan)
        #expect(model.status?.state == .running)
        #expect(model.status?.phase == .indexingAllImages)
        #expect(model.status?.discoveredPeople == 3)
        #expect(model.status?.indexedPeople == 2)
        #expect(model.status?.discoveredImages == 10)
        #expect(model.status?.scannedImages == 4)
        #expect(model.status?.remainingImages == 6)
        #expect(model.status?.percentage == 40)
        #expect(model.status?.startedAt == 1_792_620_000.25)
        #expect(model.status?.lastCompletedAt == 1_792_610_000)
        #expect(model.status?.lastError == "Previous scan failed")
    }

    @Test(arguments: [
        ConnectionFailure.serverRejected(409), .serverRejected(503), .unauthorized,
        .missingPassword, .serverRejected(500), .unreachable, .decodingFailed,
    ])
    func errorsPreserveStatusAndRescanFailuresSurviveSuccessfulRefresh(failure: ConnectionFailure) async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        let previous = model.status
        api.postError = failure
        if failure == .serverRejected(409) { api.status = Self.running }
        await model.rescan()
        #expect(model.report == nil)
        #expect(model.rescanError != nil)
        #expect(!model.isRescanning)
        #expect(model.status == api.status)
        if failure == .serverRejected(409) {
            #expect(model.rescanError?.contains("already running") == true)
            #expect(!model.canRescan)
        } else if failure == .serverRejected(503) {
            #expect(model.rescanError?.contains("unavailable") == true)
        } else {
            #expect(model.rescanError == failure.message)
        }
        let error = model.rescanError
        api.getError = failure
        await model.refreshStatus()
        #expect(model.status != nil)
        #expect(model.statusError != nil)
        #expect(!model.canRescan)
        #expect(model.rescanError == error)
        api.getError = nil
        api.status = previous!
        await model.refreshStatus()
        #expect(model.statusError == nil)
        #expect(model.rescanError == error)
        #expect(model.canRescan)
    }

    @Test func successfulReportSurvivesFailedStatusRefresh() async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        api.onRescan = { api.getError = ConnectionFailure.unreachable }
        await model.rescan()
        #expect(model.report != nil)
        #expect(model.status != nil)
        #expect(model.statusError == ConnectionFailure.unreachable.message)
        #expect(model.rescanError == nil)
        #expect(!model.canRescan)
    }

    @Test func pollsOnlyWhileRunningAndActiveAndResumesOnReturn() async {
        let api = ScanAPI()
        api.status = Self.running
        let clock = ScanClock()
        let model = LibraryScanViewModel(api: api, sleep: { try await clock.sleep() })
        let observer = UUID()
        #expect(api.gets == 0)
        model.setActive(true, observer: observer)
        await settle()
        #expect(api.gets == 1)
        #expect(clock.isWaiting)
        clock.tick()
        await settle()
        #expect(api.gets == 2)
        model.setActive(false, observer: observer)
        await settle()
        #expect(!clock.isWaiting)
        #expect(api.gets == 2)
        model.setActive(true, observer: observer)
        await settle()
        #expect(api.gets == 3)
        api.status = ScanAPI.idle
        clock.tick()
        await settle()
        #expect(api.gets == 4)
        #expect(!clock.isWaiting)
        #expect(model.canRescan)
        model.setActive(false, observer: observer)
    }

    @Test func windowsShareOnePollerAndOnlyLastInactiveWindowStopsIt() async {
        let api = ScanAPI()
        api.status = Self.running
        let clock = ScanClock()
        let model = LibraryScanViewModel(api: api, sleep: { try await clock.sleep() })
        let first = UUID()
        let second = UUID()
        model.setActive(true, observer: first)
        model.setActive(true, observer: second)
        await settle()
        #expect(api.gets == 1)
        model.setActive(false, observer: first)
        #expect(clock.isWaiting)
        clock.tick()
        await settle()
        #expect(api.gets == 2)
        model.setActive(false, observer: second)
        await settle()
        #expect(!clock.isWaiting)
    }

    @Test func idleScreenDoesNotPollAndManualRefreshStartsPollingForExternalScan() async {
        let api = ScanAPI()
        let clock = ScanClock()
        let model = LibraryScanViewModel(api: api, sleep: { try await clock.sleep() })
        let observer = UUID()
        model.setActive(true, observer: observer)
        await settle()
        #expect(api.gets == 1)
        #expect(!clock.isWaiting)
        api.status = Self.running
        await model.refreshStatus()
        await settle()
        #expect(api.gets == 2)
        #expect(clock.isWaiting)
        api.getError = ConnectionFailure.unreachable
        clock.tick()
        await settle()
        #expect(model.status == Self.running)
        #expect(model.statusError != nil)
        #expect(clock.isWaiting)
        api.getError = nil
        api.status = ScanAPI.idle
        clock.tick()
        await settle()
        #expect(model.statusError == nil)
        #expect(!clock.isWaiting)
        model.setActive(false, observer: observer)
    }

    @Test func statusKeepsUpdatingDuringRescanAndDuplicateRequestsAreIgnored() async {
        let api = ScanAPI()
        let clock = ScanClock()
        let model = LibraryScanViewModel(api: api, sleep: { try await clock.sleep() })
        let observer = UUID()
        model.setActive(true, observer: observer)
        await settle()
        var finish: CheckedContinuation<Void, Never>?
        api.onRescan = {
            api.status = Self.running
            await withCheckedContinuation { finish = $0 }
        }
        let submission = Task { await model.rescan() }
        await settle()
        #expect(model.isRescanning)
        #expect(model.status?.state == .running)
        #expect(clock.isWaiting)
        await model.rescan()
        #expect(api.posts == 1)
        clock.tick()
        await settle()
        #expect(api.gets >= 3)
        api.status = ScanAPI.idle
        finish?.resume()
        await submission.value
        #expect(model.report != nil)
        #expect(model.status?.state == .idle)
        #expect(model.canRescan)
        model.setActive(false, observer: observer)
        await settle()
    }

    @Test func connectionChangeDiscardsOldStatusAndReportEvenWhenTransportIgnoresCancellation() async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        var finish: CheckedContinuation<Void, Never>?
        api.onRescan = { await withCheckedContinuation { finish = $0 } }
        let submission = Task { await model.rescan() }
        await settle()
        api.mediaSessionID = UUID()
        model.synchronizeConnection()
        #expect(model.status == nil)
        #expect(model.report == nil)
        #expect(!model.isRescanning)
        finish?.resume()
        await submission.value
        #expect(model.status == nil)
        #expect(model.report == nil)
        #expect(model.rescanError == nil)
        await model.refreshStatus()
        #expect(model.canRescan)
    }

    @Test func cancelledRefreshDoesNotReplaceServerStatusWithError() async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        let previous = model.status
        api.getError = CancellationError()
        await model.refreshStatus()
        #expect(model.status == previous)
        #expect(model.statusError == nil)
        #expect(!model.isRefreshing)
    }

    @Test func oldStatusResponseCannotOverwriteNewConnection() async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        var finish: CheckedContinuation<Void, Never>?
        api.onStatus = { await withCheckedContinuation { finish = $0 } }
        let refresh = Task { await model.refreshStatus() }
        await settle()
        api.mediaSessionID = UUID()
        model.synchronizeConnection()
        api.onStatus = nil
        await model.refreshStatus()
        #expect(model.status == ScanAPI.idle)
        api.status = Self.running
        finish?.resume()
        await refresh.value
        #expect(model.status == ScanAPI.idle)
        #expect(model.canRescan)
    }

    @Test func failedScanRemainsVisibleAndCanBeRetried() async {
        let api = ScanAPI()
        api.status = MonekarAPI.ScanStatus(
            state: .failed, phase: .failed, discoveredPeople: 1, indexedPeople: 0,
            discoveredImages: 3, scannedImages: 0, remainingImages: 3, percentage: 0,
            startedAt: 1_792_620_000, lastCompletedAt: nil, lastError: "Library unavailable"
        )
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        #expect(model.status?.state == .failed)
        #expect(model.status?.lastError == "Library unavailable")
        #expect(model.canRescan)
        api.status = ScanAPI.idle
        await model.rescan()
        #expect(model.status?.state == .idle)
        #expect(model.report != nil)
    }

    @Test func cancelledSubmissionRechecksStatusBeforeAllowingRetry() async {
        let api = ScanAPI()
        let model = LibraryScanViewModel(api: api)
        await model.refreshStatus()
        api.postError = CancellationError()
        api.status = Self.running
        await model.rescan()
        #expect(model.rescanError?.contains("interrupted") == true)
        #expect(model.status?.state == .running)
        #expect(!model.canRescan)
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
    }

    private static let running = MonekarAPI.ScanStatus(
        state: .running, phase: .indexingAllImages, discoveredPeople: 3, indexedPeople: 2,
        discoveredImages: 10, scannedImages: 4, remainingImages: 6, percentage: 40,
        startedAt: 1_792_620_000.25, lastCompletedAt: 1_792_610_000,
        lastError: "Previous scan failed"
    )
}

@MainActor
private final class ScanAPI: APIService {
    var baseURL: URL? = URL(string: "https://server.invalid")
    var mediaSessionID: UUID? = UUID()
    var status = idle
    var getError: (any Error)?
    var postError: (any Error)?
    var onStatus: (() async -> Void)?
    var onRescan: (() async -> Void)?
    var gets = 0
    var posts = 0

    static let idle = MonekarAPI.ScanStatus(
        state: .idle, phase: .complete, discoveredPeople: 1, indexedPeople: 1,
        discoveredImages: 3, scannedImages: 3, remainingImages: 0, percentage: 100,
        startedAt: nil, lastCompletedAt: 1_792_620_000, lastError: nil
    )

    func configure(_ configuration: ServerConnection?) { baseURL = configuration?.baseURL }
    func verifyConnection(_ configuration: ServerConnection?) async throws {}
    func get(path: [String]) async throws -> Data { Data() }
    func get(mediaReference: String) async throws -> Data { Data() }

    func request(_ request: APIRequest) async throws -> Data {
        if request.path == ["api", "v1", "library", "scan-status"] {
            #expect(request.method == .get)
            gets += 1
            await onStatus?()
            if let getError { throw getError }
            return try JSONEncoder().encode(status)
        }
        #expect(request.path == ["api", "v1", "library", "rescan"])
        #expect(request.method == .post)
        posts += 1
        await onRescan?()
        if let postError { throw postError }
        return Data("""
        {"people":1,"albums":2,"images":3,"ignoredFiles":4,"removedImages":5,
        "pruned":true,"issues":[{"reason":"Unreadable entry"}]}
        """.utf8)
    }
}

@MainActor
private final class ScanClock {
    private var continuation: CheckedContinuation<Void, any Error>?
    var isWaiting: Bool { continuation != nil }

    func sleep() async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    func tick() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }

    private func cancel() {
        let pending = continuation
        continuation = nil
        pending?.resume(throwing: CancellationError())
    }
}
