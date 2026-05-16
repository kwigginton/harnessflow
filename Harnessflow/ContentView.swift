import AppKit
import SwiftUI
import HarnessflowCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingCreateProjectSheet = false

    var body: some View {
        PersistentHSplitView(
            autosaveKey: "content.split.trailingFraction",
            defaultTrailingFraction: 0.24,
            minLeadingWidth: 980,
            minTrailingWidth: 280
        ) {
            BoardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } trailing: {
            TicketDetailView(ticket: store.selectedTicket)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Harnessflow")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingCreateProjectSheet = true
                } label: {
                    Label("Add Working Directory", systemImage: "plus")
                }
                .help("Add Working Directory")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingCreateProjectSheet) {
            CreateProjectSheet(isPresented: $isShowingCreateProjectSheet)
                .environmentObject(store)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { newValue in
                    if newValue == false {
                        store.clearError()
                    }
                }
            ),
            actions: {
                if store.errorRecoveryAction != nil {
                    Button(store.errorRecoveryAction?.title ?? "Recover") {
                        store.performErrorRecoveryAction()
                    }
                }

                Button("OK", role: .cancel) {
                    store.clearError()
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
    }
}

private struct CreateProjectSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var workingDirectory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Working Directory")
                .font(.title3.weight(.semibold))

            TextField("Directory Name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Working Directory")
                    .font(.subheadline.weight(.medium))

                Text(workingDirectory.isEmpty ? "No folder selected" : workingDirectory)
                    .font(.callout)
                    .foregroundStyle(workingDirectory.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button("Choose Folder…") {
                    let startingDirectory = workingDirectory.isEmpty ? store.selectedProject?.workingDirectory : workingDirectory
                    if let selectedDirectory = chooseDirectory(startingAt: startingDirectory) {
                        workingDirectory = selectedDirectory
                    }
                }
            }

            if store.archivedDirectorySummaries.isEmpty == false {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prior Directories")
                        .font(.subheadline.weight(.semibold))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(store.archivedDirectorySummaries) { summary in
                                ArchivedDirectorySummaryRow(summary: summary) {
                                    store.restoreDirectoryRow(projectID: summary.project.id)
                                    if store.errorMessage == nil {
                                        resetForm()
                                        isPresented = false
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    resetForm()
                    isPresented = false
                }

                Button("Add") {
                    store.createProject(name: name, workingDirectory: workingDirectory)
                    if store.errorMessage == nil {
                        resetForm()
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workingDirectory.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear(perform: resetForm)
    }

    private func resetForm() {
        name = ""
        workingDirectory = store.selectedProject?.workingDirectory ?? FileManager.default.currentDirectoryPath
    }
}

private struct ArchivedDirectorySummaryRow: View {
    let summary: AppStore.ArchivedDirectorySummary
    let onRestore: () -> Void

    private var phaseSummary: String {
        [
            ("R", summary.researchCount),
            ("P", summary.planCount),
            ("I", summary.implementCount),
            ("V", summary.reviewCount),
        ]
        .map { "\($0.0) \($0.1)" }
        .joined(separator: "  ")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(summary.project.name)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)

                    Text("\(summary.totalCount) tasks")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(summary.project.workingDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text("\(summary.activeCount) active  \(summary.doneCount) done  \(summary.runningCount) running  \(phaseSummary)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button("Restore", action: onRestore)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

@MainActor
private func chooseDirectory(startingAt path: String?) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose Folder"

    if let path, path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
        panel.directoryURL = URL(fileURLWithPath: path)
    }

    let response = panel.runModal()
    guard response == .OK else {
        return nil
    }
    return panel.url?.path
}
