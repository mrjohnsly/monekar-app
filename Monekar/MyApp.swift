import SwiftUI

@main struct Monekar: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

//@main struct MyApp: App {
//    private let services: AppServices
//
//    init() {
//        #if DEBUG
//        if ProcessInfo.processInfo.arguments.contains("--test-model-navigation") {
//            services = ModelNavigationTestServices.make()
//            return
//        }
//        #endif
//        let credentials = KeychainCredentialService(service: Bundle.main.bundleIdentifier ?? "Monekar")
//        let connectionMetadata = UserDefaultsConnectionMetadataService()
//        services = AppServices(
//            api: URLSessionAPIService(
//                configuration: connectionMetadata.configuration,
//                credentials: credentials
//            ),
//            credentials: credentials,
//            connectionMetadata: connectionMetadata
//        )
//    }
//
//    var body: some Scene {
//        WindowGroup {
//            ContentView(models: WindowModels(services: services), presentation: ImagePresentation())
//                .environment(services)
//        }
//    }
//}
