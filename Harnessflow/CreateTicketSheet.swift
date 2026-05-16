import SwiftUI
import HarnessflowCore

struct CreateTicketSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    let project: ProjectRecord
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

            Toggle("Auto-shift on successful completion", isOn: $autoShiftOnSuccess)

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
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear(perform: resetForm)
    }

    private func resetForm() {
        title = ""
        detailsText = ""
        startingPhase = .research
        autoShiftOnSuccess = false
    }
}
