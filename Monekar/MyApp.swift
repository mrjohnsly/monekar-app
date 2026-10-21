import SwiftUI

@main struct MyApp: App {
    private let services: AppServices

    init() {
        let credentials = KeychainCredentialService(service: Bundle.main.bundleIdentifier ?? "Monekar")
        // No server endpoint is assumed before the client is configured.
        let serverURL = (Bundle.main.object(forInfoDictionaryKey: "MonekarServerURL") as? String)
            .flatMap(URL.init(string:))
        services = AppServices(
            api: URLSessionAPIService(baseURL: serverURL, credentials: credentials),
            credentials: credentials
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(services: services)
        }
    }
}
