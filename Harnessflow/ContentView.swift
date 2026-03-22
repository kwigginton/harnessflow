import AppKit
import SwiftUI
import HarnessflowCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingCreateSheet = false
    @State private var isShowingCreateProjectSheet = false

    private var projectMenuTitle: String {
        store.selectedProject?.name ?? "Project"
    }

    private var directoryMenuTitle: String {
        guard let workingDirectory = store.selectedProject?.workingDirectory else {
            return "Directory"
        }

        let lastPathComponent = URL(fileURLWithPath: workingDirectory).lastPathComponent
        return lastPathComponent.isEmpty ? workingDirectory : lastPathComponent
    }

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
            ToolbarItem {
                ProjectToolbarControl(
                    title: projectMenuTitle,
                    projects: store.projects,
                    selectedProjectID: store.selectedProjectID,
                    onSelectProject: store.selectProject(_:),
                    onCreateProject: {
                        isShowingCreateProjectSheet = true
                    }
                )
            }

            ToolbarItemGroup {
                Menu {
                    if let project = store.selectedProject {
                        Text(project.workingDirectory)
                            .textSelection(.enabled)

                        Divider()

                        Button("Choose Folder…") {
                            chooseProjectDirectory()
                        }
                    } else {
                        Text("No Project Selected")
                    }
                } label: {
                    Label(directoryMenuTitle, systemImage: "folder")
                }
                .disabled(store.hasSelectedProject == false)

                Button {
                    isShowingCreateSheet = true
                } label: {
                    Label("Create Ticket", systemImage: "plus.rectangle.on.rectangle")
                }
                .disabled(store.hasSelectedProject == false)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateTicketSheet(isPresented: $isShowingCreateSheet)
                .environmentObject(store)
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
                Button("OK", role: .cancel) {
                    store.clearError()
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
    }

    private func chooseProjectDirectory() {
        guard let project = store.selectedProject else {
            return
        }
        guard let selectedDirectory = chooseDirectory(startingAt: project.workingDirectory) else {
            return
        }
        store.updateSelectedProjectDirectory(selectedDirectory)
    }
}

private struct CreateProjectSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var workingDirectory = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Project")
                .font(.title3.weight(.semibold))

            TextField("Project Name", text: $name)
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

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    resetForm()
                    isPresented = false
                }

                Button("Create") {
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
        .frame(width: 460)
        .onAppear(perform: resetForm)
    }

    private func resetForm() {
        name = ""
        workingDirectory = store.selectedProject?.workingDirectory ?? FileManager.default.currentDirectoryPath
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

private struct ProjectToolbarControl: View {
    let title: String
    let projects: [ProjectRecord]
    let selectedProjectID: UUID?
    let onSelectProject: (UUID) -> Void
    let onCreateProject: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                if projects.isEmpty {
                    Text("No Projects")
                } else {
                    ForEach(projects) { project in
                        Button {
                            onSelectProject(project.id)
                        } label: {
                            if project.id == selectedProjectID {
                                Label(project.name, systemImage: "checkmark")
                            } else {
                                Text(project.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                    Text(title)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.leading, 12)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.plain)
            .fixedSize()

            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 1, height: 16)
                .padding(.vertical, 4)

            Button(action: onCreateProject) {
                Image(systemName: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .help("Create Project")
        }
    }
}
