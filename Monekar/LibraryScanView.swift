import SwiftUI

struct LibraryScanView: View {
    @Environment(AppServices.self) private var services
    private var viewModel: LibraryScanViewModel { services.libraryScan }
    @Environment(\.scenePhase) private var scenePhase
    @State private var observer = UUID()
    @State private var isVisible = false

    var body: some View {
        Form {
            Section("Scan status") {
                if let status = viewModel.status {
                    LabeledContent("State", value: status.state.rawValue.capitalized)
                    LabeledContent("Phase", value: status.phase.rawValue.capitalized)
                    ProgressView(value: min(max(status.percentage, 0), 100), total: 100) {
                        Text("Scan progress")
                    } currentValueLabel: {
                        Text("\(status.percentage, specifier: "%.1f")%")
                    }
                    .accessibilityValue("\(status.percentage, specifier: "%.1f") percent")
                    LabeledContent("People discovered", value: status.discoveredPeople.formatted())
                    LabeledContent("People indexed", value: status.indexedPeople.formatted())
                    LabeledContent("Images discovered", value: status.discoveredImages.formatted())
                    LabeledContent("Images indexed", value: status.scannedImages.formatted())
                    LabeledContent("Images remaining", value: status.remainingImages.formatted())
                    timestamp("Started", seconds: status.startedAt)
                    timestamp("Last completed", seconds: status.lastCompletedAt)
                    if let error = status.lastError, !error.isEmpty {
                        errorLabel("Last scan error: \(error)")
                    }
                    Text("Last received server status. Refresh errors do not clear these values.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.isRefreshing {
                    ProgressView("Loading scan status…")
                } else {
                    Text("Scan status has not been received.")
                }
                if let error = viewModel.statusError {
                    errorLabel(error)
                }
                Button("Refresh Status") {
                    Task { await viewModel.refreshStatus() }
                }
                .disabled(viewModel.isRefreshing)
            }

            Section("Rescan library") {
                Button("Rescan Library", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await viewModel.rescan() }
                }
                .disabled(!viewModel.canRescan)
                .accessibilityIdentifier("rescanLibrary")
                if viewModel.isRescanning {
                    ProgressView("Waiting for the server’s scan report…")
                } else if viewModel.status?.state == .running {
                    Text("A scan is running. Another scan cannot be started.")
                }
                if let error = viewModel.rescanError {
                    errorLabel(error)
                }
            }

            if let report = viewModel.report {
                Section("Rescan report") {
                    LabeledContent("People", value: report.people.formatted())
                    LabeledContent("Albums", value: report.albums.formatted())
                    LabeledContent("Images", value: report.images.formatted())
                    LabeledContent("Ignored files", value: report.ignoredFiles.formatted())
                    LabeledContent("Removed images", value: report.removedImages.formatted())
                    LabeledContent("Pruned", value: report.pruned ? "Yes" : "No")
                    LabeledContent("Issues", value: report.issues.count.formatted())
                    ForEach(report.issues.indices, id: \.self) { index in
                        errorLabel(report.issues[index].reason)
                    }
                }
            }
        }
        .navigationTitle("Library Scan")
        .accessibilityIdentifier("libraryScanScreen")
        .onAppear {
            isVisible = true
            updateActivity()
        }
        .onDisappear {
            isVisible = false
            updateActivity()
        }
        .onChange(of: scenePhase) { _, _ in updateActivity() }
    }

    private func timestamp(_ title: String, seconds: TimeInterval?) -> some View {
        LabeledContent(title) {
            if let seconds {
                Text(Date(timeIntervalSince1970: seconds), format: .dateTime)
            } else {
                Text("Not available")
            }
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(.red)
        .accessibilityElement(children: .combine)
    }

    private func updateActivity() {
        viewModel.setActive(isVisible && scenePhase == .active, observer: observer)
    }
}
