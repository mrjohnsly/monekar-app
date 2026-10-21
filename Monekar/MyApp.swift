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
        #if os(macOS)
        WindowGroup("Image", for: MonekarAPI.Image.self) { $image in
            if let image {
                ImageViewer(image: image, services: services)
                    .frame(minWidth: 320, minHeight: 240)
            }
        }
        .defaultSize(width: 1000, height: 800)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        #endif
    }
}
