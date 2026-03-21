import SwiftUI
import HarnessflowCore

struct TicketDetailView: View {
    @EnvironmentObject private var store: AppStore
    let ticket: Ticket?
    @State private var promptDraft = ""

    var body: some View {
        Group {
            if let ticket {
                detail(for: ticket)
            } else {
                ContentUnavailableView(
                    "Select a Ticket",
                    systemImage: "rectangle.stack",
                    description: Text("Choose a card from the board to edit its prompt, inspect history, or run the current phase.")
                )
            }
        }
        .padding(20)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func detail(for ticket: Ticket) -> some View {
        let phase = ticket.column
        let phaseState = ticket.phaseState(for: phase)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(ticket.title)
                        .font(.title2.weight(.semibold))

                    if ticket.detailsText.isEmpty == false {
                        Text(ticket.detailsText)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Label(phase.title, systemImage: phase.symbolName)
                            .font(.callout.weight(.semibold))
                        StatusBadge(state: phaseState.executionState)
                        Text("Model: \(store.settings.phaseModels.model(for: phase))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                GroupBox("Agent Prompt") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $promptDraft)
                            .font(.body.monospaced())
                            .frame(minHeight: 140)

                        HStack {
                            Button("Save Prompt") {
                                store.savePrompt(for: ticket.id, prompt: promptDraft)
                            }

                            Button {
                                store.savePrompt(for: ticket.id, prompt: promptDraft)
                                Task {
                                    await store.runCurrentPhase(for: ticket.id)
                                }
                            } label: {
                                Label(
                                    phaseState.executionState == .running ? "Running..." : "Run \(phase.title)",
                                    systemImage: "play.fill"
                                )
                            }
                            .disabled(phaseState.executionState == .running)

                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Latest Result") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let startedAt = phaseState.lastStartedAt {
                            Text("Started: \(startedAt.formatted(date: .numeric, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if let completedAt = phaseState.lastCompletedAt {
                            Text("Completed: \(completedAt.formatted(date: .numeric, time: .shortened))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if phaseState.capturedOutput.isEmpty == false {
                            OutputBlock(title: "Output", text: phaseState.capturedOutput)
                        }

                        if phaseState.capturedError.isEmpty == false {
                            OutputBlock(title: "Error", text: phaseState.capturedError)
                        }

                        if phaseState.capturedOutput.isEmpty && phaseState.capturedError.isEmpty {
                            Text("No execution result captured for this phase yet.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Run History") {
                    VStack(alignment: .leading, spacing: 10) {
                        if phaseState.runs.isEmpty {
                            Text("No runs yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(phaseState.runs.reversed()) { run in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(run.success ? "Completed" : "Failed")
                                            .font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(run.completedAt.formatted(date: .numeric, time: .shortened))
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text("Model: \(run.model)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)

                                    Text(run.prompt)
                                        .font(.footnote.monospaced())
                                        .lineLimit(3)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .onAppear {
            promptDraft = phaseState.prompt
        }
        .onChange(of: ticket.id) { _, _ in
            promptDraft = ticket.phaseState(for: ticket.column).prompt
        }
        .onChange(of: phaseState.prompt) { _, _ in
            if phaseState.prompt != promptDraft, phaseState.executionState != .running {
                promptDraft = phaseState.prompt
            }
        }
    }
}

private struct StatusBadge: View {
    let state: PhaseExecutionState

    private var color: Color {
        switch state {
        case .idle:
            .secondary
        case .running:
            .orange
        case .completed:
            .green
        case .failed:
            .red
        }
    }

    var body: some View {
        Text(state.displayTitle)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct OutputBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ScrollView {
                Text(text)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 90, maxHeight: 180)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
