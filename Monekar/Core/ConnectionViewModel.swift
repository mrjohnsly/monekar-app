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

    init(services: AppServices) {
        self.services = services
        let configuration = services.connectionMetadata.configuration
        serverURL = configuration?.baseURL.absoluteString ?? ""
        username = configuration?.username ?? ""
        hasSavedConnection = configuration != nil
    }

    func verifyAndSave() async {
        guard state != .checking else { return }
        state = .checking

        do {
            let configuration = try ServerConnection(serverURL: serverURL, username: username)
            let savedPassword = password.isEmpty ? try await services.credentials.password() : password
            guard let savedPassword, !savedPassword.isEmpty else {
                state = .failed(.missingPassword)
                return
            }
            try await services.api.verifyConnection(configuration)
            try await services.credentials.setPassword(savedPassword)
            try services.connectionMetadata.save(configuration)
            services.api.configure(configuration)
            serverURL = configuration.baseURL.absoluteString
            username = configuration.username
            password = ""
            hasSavedConnection = true
            state = .connected
        } catch is CancellationError {
            state = .idle
        } catch let error as ConnectionConfigurationError {
            state = .failed(error == .missingUsername ? .missingUsername : .invalidURL)
        } catch let failure as ConnectionFailure {
            state = .failed(failure)
        } catch let error as CredentialError {
            state = .failed(.credentialStorage(error.status))
        } catch {
            state = .failed(.storageFailure)
        }
    }

    func removeConnection() async {
        guard state != .checking else { return }
        do {
            try services.connectionMetadata.remove()
            try await services.credentials.setPassword(nil)
            services.api.configure(nil)
            hasSavedConnection = false
            serverURL = ""
            username = ""
            password = ""
            state = .removed
        } catch {
            if let error = error as? CredentialError {
                state = .failed(.credentialStorage(error.status))
            } else {
                state = .failed(.storageFailure)
            }
        }
    }
}
