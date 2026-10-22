import Foundation
import Observation

enum ConnectionViewState: Equatable {
    case idle
    case checking
    case connected
    case removed
    case failed(ConnectionFailure)
}

@MainActor
@Observable
final class ConnectionViewModel {
    var serverURL: String
    var username: String
    var password = ""
    private(set) var state: ConnectionViewState = .idle
    private(set) var hasSavedConnection: Bool

    private let services: AppServices
    private var connectionRevision: UUID

    init(services: AppServices) {
        self.services = services
        connectionRevision = services.connectionRevision
        let configuration = services.connectionMetadata.configuration
        serverURL = configuration?.baseURL.absoluteString ?? ""
        username = configuration?.username ?? ""
        hasSavedConnection = configuration != nil
    }

    func synchronizeConnection() {
        guard connectionRevision != services.connectionRevision else { return }
        connectionRevision = services.connectionRevision
        let configuration = services.connectionMetadata.configuration
        serverURL = configuration?.baseURL.absoluteString ?? ""
        username = configuration?.username ?? ""
        password = ""
        hasSavedConnection = configuration != nil
        state = .idle
    }

    func verifyAndSave() async {
        synchronizeConnection()
        guard state != .checking else { return }
        let revision = services.connectionRevision
        state = .checking

        do {
            let configuration = try ServerConnection(serverURL: serverURL, username: username)
            let savedPassword = password.isEmpty ? try await services.credentials.password() : password
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            guard let savedPassword, !savedPassword.isEmpty else {
                state = .failed(.missingPassword)
                return
            }
            try await services.api.verifyConnection(configuration)
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            try await services.credentials.setPassword(savedPassword)
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            try services.connectionMetadata.save(configuration)
            services.api.configure(configuration)
            services.connectionDidChange()
            connectionRevision = services.connectionRevision
            serverURL = configuration.baseURL.absoluteString
            username = configuration.username
            password = ""
            hasSavedConnection = true
            state = .connected
        } catch {
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            switch error {
            case is CancellationError:
                state = .idle
            case let error as ConnectionConfigurationError:
                state = .failed(error == .missingUsername ? .missingUsername : .invalidURL)
            case let failure as ConnectionFailure:
                state = .failed(failure)
            case let error as CredentialError:
                state = .failed(.credentialStorage(error.status))
            default:
                state = .failed(.storageFailure)
            }
        }
    }

    func removeConnection() async {
        synchronizeConnection()
        guard state != .checking else { return }
        let revision = services.connectionRevision
        do {
            try services.connectionMetadata.remove()
            try await services.credentials.setPassword(nil)
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            services.api.configure(nil)
            services.connectionDidChange()
            connectionRevision = services.connectionRevision
            hasSavedConnection = false
            serverURL = ""
            username = ""
            password = ""
            state = .removed
        } catch {
            guard revision == services.connectionRevision else {
                synchronizeConnection()
                return
            }
            if let error = error as? CredentialError {
                state = .failed(.credentialStorage(error.status))
            } else {
                state = .failed(.storageFailure)
            }
        }
    }
}
