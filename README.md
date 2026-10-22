# Monekar

Monekar is a universal SwiftUI client for a monekar-server installation.

## Platforms and tools

The app supports iOS 27 and macOS 27. Use Xcode 27 or newer (Swift 6.4 or newer) to build and run the app and its unit/UI tests. The shared `Monekar` scheme runs both test targets.

### macOS Keychain access when running from Xcode

Monekar uses the data-protection keychain on both platforms. On macOS, the app's Keychain access group is scoped to its signing team and bundle identifier, rather than the legacy login keychain's per-application access list.

In Xcode, select the Monekar target's **Signing & Capabilities**, enable automatic signing, and select your development team. Use **Apple Development** signing (not **Sign to Run Locally** / ad-hoc signing), and keep the team and bundle identifier unchanged between builds. No team identifier is committed to the project; each developer selects their own. Do not disable signing or broaden the Keychain item's access to all applications to suppress prompts.

If you previously saved a password with the macOS version, open the connection screen and enter and save the password again once. The old login-keychain entry is deliberately not read or automatically migrated, since reading it can trigger the same prompt. After saving successfully, you may remove only the obsolete Monekar login-keychain password entry (service matching the app's bundle identifier, account `server-password`) in Keychain Access. Changing signing teams or bundle identifiers also requires entering the password again.

To verify on macOS, save a connection, quit the app, change a source file, and rebuild and run from Xcode with the same signing settings. The saved connection should still work without the recurring login-keychain permission prompt. A locked keychain or device authentication policy can still require authentication.

## Architecture

`Monekar/Core` contains the API contract, transport, connection and credential abstractions, and observable view models. It is built directly by SwiftPM so this logic can be tested without SwiftUI or a server. SwiftUI screens live under `Monekar/` and use view models rather than making network requests directly. `AppServices` supplies shared API, Keychain credential, media, image-library, and scan services.

`MyApp` creates shared `AppServices` and a separate screen-model graph and image presentation for each window, injecting them through SwiftUI's environment. `ContentView` retains the window objects in state and declares `ModelsView`, `FavouritesView`, `TagsView`, and `SettingsView` as sidebar-adaptable tabs. Each tab owns a native `NavigationStack` with direct `NavigationLink` destinations, without a coordinator or navigation wrapper. `WindowModels` owns the connection form and a browsing graph containing separate connection-loading models per tab, people pagination, favourites, tags, and cached person/album/tag detail models. Screens read these observable models from the graph or receive them from their parent; image grids open the window's image presentation directly. Connection setup and shared library scanning are available under Settings; browsing tabs show connection or sign-in guidance until configured. Successful connection saves/removals update `AppServices.connectionRevision`: each window resolves a fresh browsing graph before resetting its stacks, dismisses its image viewer, and synchronizes its connection form when another window changes the server. Settings navigation and the saving/removing form remain intact.

## Connecting to a local server

Enter the server installation root as the base URL, including any reverse-proxy prefix, but not `/api/v1` (for example, `https://monekar.local:8443/photos`). The app checks the public `/health` route and sends Basic authentication to protected API and same-origin media routes.

For HTTPS, the server must present a valid certificate chain trusted by the operating system, with a subject alternative name matching the host used in the URL. For a private development CA, install and trust its root certificate on the Mac or iOS device running the app. Do not use a self-signed leaf certificate unless it is explicitly trusted by the operating system. Monekar does not bypass TLS certificate verification.

## Running tests

The tests use in-memory API and HTTP transport doubles; they do not need a running server or real credentials.

Run the shared core tests with Swift 6.4 or newer:

```sh
swift test
```

Run the Xcode unit and UI test targets on macOS with an installed simulator destination:

```sh
xcodebuild test -project Monekar.xcodeproj -scheme Monekar \
  -destination 'platform=iOS Simulator,name=<installed simulator>'
```

`APIClientTests` covers the API request/response contract, DTO decoding, pagination, authentication, binary media, and HTTP failures. `ServerConnectionTests`, `GalleryViewModelTests`, `ImageManagementTests`, `MediaLoaderTests`, and `LibraryScanViewModelTests` cover connection and core app flows.

`KeychainCredentialServiceTests` runs only in the signed Xcode unit-test host, not SwiftPM. It uses a unique temporary Keychain service and removes its item after testing. To run it on macOS with the signing setup above:

```sh
xcodebuild test -project Monekar.xcodeproj -scheme Monekar \
  -destination 'platform=macOS' \
  -only-testing:MonekarTests/KeychainCredentialServiceTests
```
