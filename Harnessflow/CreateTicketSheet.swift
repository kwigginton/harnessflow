import SwiftUI
import HarnessflowCore

private enum CreateTicketMode: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case linear = "Linear"

    var id: Self { self }
}

struct CreateTicketSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    let project: ProjectRecord
    @State private var mode: CreateTicketMode = .manual
    @State private var linearIdentifier = ""
    @State private var isImportingLinearIssue = false
    @State private var linearImportError: String?
    @State private var title = ""
    @State private var detailsText = ""
    @State private var startingPhase: TicketPhase = .research
    @State private var autoShiftOnSuccess = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Ticket")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.subheadline.weight(.semibold))
                Text(project.workingDirectory)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Picker("Create Mode", selection: $mode) {
                ForEach(CreateTicketMode.allCases) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .linear {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Linear issue identifier", text: $linearIdentifier)
                            .textFieldStyle(.roundedBorder)

                        Button("Import") {
                            importLinearIssue()
                        }
                        .disabled(isImportingLinearIssue || linearIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if isImportingLinearIssue {
                        ProgressView("Importing from Linear...")
                            .controlSize(.small)
                    } else if let linearImportError {
                        Label(linearImportError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else {
                        Text("Imported content remains editable before the ticket is created.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Starting Phase")
                    .font(.subheadline.weight(.medium))

                HStack(spacing: 10) {
                    PhaseIcon(phase: startingPhase, size: 18)

                    Picker("Starting Phase", selection: $startingPhase) {
                        ForEach(TicketPhase.allCases) { phase in
                            Text(phase.title)
                                .tag(phase)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $detailsText)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }

            Toggle("Auto-run next phase on success", isOn: $autoShiftOnSuccess)

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    resetForm()
                    isPresented = false
                }

                Button("Create") {
                    store.createTicket(
                        title: title,
                        detailsText: detailsText,
                        projectID: project.id,
                        initialPhase: startingPhase,
                        autoShiftOnSuccess: autoShiftOnSuccess
                    )
                    if store.errorMessage == nil {
                        resetForm()
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isImportingLinearIssue)
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear(perform: resetForm)
    }

    private func resetForm() {
        mode = .manual
        linearIdentifier = ""
        isImportingLinearIssue = false
        linearImportError = nil
        title = ""
        detailsText = ""
        startingPhase = .research
        autoShiftOnSuccess = false
    }

    private func importLinearIssue() {
        let identifier = linearIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard identifier.isEmpty == false else {
            linearImportError = LinearImportError.missingIdentifier.localizedDescription
            return
        }

        isImportingLinearIssue = true
        linearImportError = nil

        Task {
            do {
                let issue = try await store.importLinearIssue(identifier: identifier)
                title = issue.harnessflowTitle
                detailsText = LinearIssueImportFormatter().markdown(for: issue)
            } catch {
                linearImportError = error.localizedDescription
            }
            isImportingLinearIssue = false
        }
    }
}
