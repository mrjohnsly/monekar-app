import SwiftUI

struct ConnectionView: View {
    @Environment(WindowModels.self) private var models
    @Environment(\.dismiss) private var dismiss

    private var viewModel: ConnectionViewModel { models.connection }

    var body: some View {
        @Bindable var viewModel = viewModel
        Form {
            Section("Server connection") {
                TextField("http://server.local:8080", text: $viewModel.serverURL)
                    .textContentType(.URL)
                TextField("Username", text: $viewModel.username)
                    .textContentType(.username)
                SecureField(
                    viewModel.hasSavedConnection ? "Password (blank keeps saved password)" : "Password",
                    text: $viewModel.password
                )
                .textContentType(.password)

                Button(viewModel.hasSavedConnection ? "Verify & Sign In" : "Verify & Connect") {
                    Task {
                        await viewModel.verifyAndSave()
                    }
                }
                .disabled(viewModel.state == .checking)
                .accessibilityIdentifier("verifyConnection")

                if viewModel.state == .checking {
                    ProgressView("Checking server…")
                } else if viewModel.state == .connected {
                    Text("Server is reachable. Protected requests use HTTP Basic credentials.")
                        .foregroundStyle(.green)
                } else if case .failed(let failure) = viewModel.state {
                    Text(failure.message)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("connectionError")
                } else if viewModel.state == .removed {
                    Text("Connection removed.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Network and security") {
                Text("HTTP Basic credentials are not encrypted by HTTP. Use HTTP only on a trusted local network or Tailscale. HTTPS uses normal system certificate validation; a direct local or Tailscale connection does not need an HTTPS certificate.")
                Text("Allow Monekar to access your local network when iOS or iPadOS asks. If access is denied, enable it in Settings > Privacy & Security > Local Network.")
            }

            if viewModel.hasSavedConnection {
                Section {
                    Button("Remove connection", role: .destructive) {
                        Task {
                            await viewModel.removeConnection()
                        }
                    }
                    .accessibilityIdentifier("removeConnection")
                }
            }

            Button("Done") { dismiss() }
                .accessibilityIdentifier("closeConnection")
        }
        .padding()
        .navigationTitle("Connection")
        .accessibilityIdentifier("connectionScreen")
        .onAppear { viewModel.synchronizeConnection() }
    }
}
