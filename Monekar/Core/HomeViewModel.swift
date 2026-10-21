import Foundation
import Observation

enum LoadState<Value: Equatable>: Equatable {
    case idle
    case loading
    case empty
    case loaded(Value)
    case failed
}

struct ConnectionSummary: Equatable {
    let serverURL: URL
    let hasCredential: Bool
}

@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: LoadState<ConnectionSummary> = .idle
    private let services: AppServices

    init(services: AppServices) {
        self.services = services
    }

    func load() async {
        guard state != .loading else { return }
        let previousState = state
        state = .loading

        do {
            guard let serverURL = services.api.baseURL else {
                state = .empty
                return
            }
            let token = try await services.credentials.accessToken()
            try Task.checkCancellation()
            state = .loaded(ConnectionSummary(
                serverURL: serverURL,
                hasCredential: token?.isEmpty == false
            ))
        } catch is CancellationError {
            state = previousState
        } catch {
            // Never surface credential or transport error descriptions in the UI.
            state = .failed
        }
    }
}
