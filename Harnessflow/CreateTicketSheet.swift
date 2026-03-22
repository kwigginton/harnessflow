import SwiftUI
import HarnessflowCore

struct CreateTicketSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var detailsText = ""
    @State private var startingPhase: TicketPhase = .research

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Ticket")
                .font(.title3.weight(.semibold))

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

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    resetForm()
                    isPresented = false
                }

                Button("Create") {
                    store.createTicket(title: title, detailsText: detailsText, initialPhase: startingPhase)
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
    }
}
