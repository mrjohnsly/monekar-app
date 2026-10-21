import SwiftUI

@main struct MyApp: App {
    private let services: AppServices

    init() {
        let credentials = KeychainCredentialService(service: Bundle.main.bundleIdentifier ?? "Monekar")
        let connectionMetadata = UserDefaultsConnectionMetadataService()
        services = AppServices(
            api: URLSessionAPIService(
                configuration: connectionMetadata.configuration,
                credentials: credentials
            ),
            credentials: credentials,
            connectionMetadata: connectionMetadata
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
        }
    }
}
