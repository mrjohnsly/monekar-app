# Monekar

Monekar is a universal SwiftUI client for a monekar-server installation.

## Platforms and tools

The app supports iOS 27 and macOS 27. Use Xcode 27 or newer (Swift 6.4 or newer) to build and run the app and its unit/UI tests. The shared `Monekar` scheme runs both test targets.

## Architecture

`Monekar/Core` contains the API contract, transport, connection and credential abstractions, observable view models, and app coordinator. It is built directly by SwiftPM so this logic can be tested without SwiftUI or a server. SwiftUI screens live under `Monekar/` and use the coordinator and view models rather than making network requests directly. `AppServices` supplies shared API, Keychain credential, media, image-library, and scan services.

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
