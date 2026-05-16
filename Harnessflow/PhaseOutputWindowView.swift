import SwiftUI
import HarnessflowCore

struct PhaseOutputWindowRoute: Hashable, Codable {
    let ticketID: UUID
    let phaseRawValue: Int

    init(ticketID: UUID, phase: TicketPhase) {
        self.ticketID = ticketID
        self.phaseRawValue = phase.rawValue
    }

    var phase: TicketPhase? {
        TicketPhase(rawValue: phaseRawValue)
    }
}

struct PhaseOutputWindowView: View {
    @EnvironmentObject private var store: AppStore
    let route: PhaseOutputWindowRoute?

    private let bottomAnchor = "phase-output-bottom"

    var body: some View {
        Group {
            if let route, let phase = route.phase {
                content(ticketID: route.ticketID, phase: phase)
            } else {
                ContentUnavailableView(
                    "Output Unavailable",
                    systemImage: "terminal",
                    description: Text("The requested phase output could not be opened.")
                )
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    @ViewBuilder
    private func content(ticketID: UUID, phase: TicketPhase) -> some View {
        let ticket = store.ticket(withID: ticketID)
        let liveOutput = store.liveOutput(for: ticketID, phase: phase)
        let persistedState = ticket?.phaseState(for: phase)
        let outputText = visibleDisplayText(liveOutput: liveOutput, persistedState: persistedState)
        let liveOutputRevision = liveOutput?.lastUpdatedAt

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ticket?.title ?? "Ticket")
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    PhaseLabel(phase: phase, font: .callout.weight(.semibold), iconSize: 18)

                    if let liveOutput {
                        StatusBadge(state: liveOutput.isRunning ? .running : (persistedState?.executionState ?? .idle))
                        Text(
                            liveOutput.processIdentifier.map { "PID \($0)" }
                                ?? (liveOutput.isRunning ? "Launching…" : "Detached")
                        )
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                    } else if let persistedState {
                        StatusBadge(state: persistedState.executionState)
                    }

                    Spacer()

                    if let updatedAt = liveOutput?.lastUpdatedAt ?? persistedState?.lastCompletedAt {
                        Text(updatedAt.formatted(date: .numeric, time: .standard))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if persistedState?.executionState == .running {
                    if let persistedState, persistedState.ownedProcess != nil {
                        Text(processSummary(for: persistedState, liveOutput: liveOutput))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Terminate Process") {
                                store.terminateOwnedProcess(ticketID: ticketID, phase: phase)
                            }

                            Button("Force Kill") {
                                store.terminateOwnedProcess(ticketID: ticketID, phase: phase, force: true)
                            }
                        }
                    } else {
                        Text("This running state has no recorded process ownership. It can be cleared, but not terminated from Harnessflow.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button("Clear Running State") {
                            store.clearStuckRunningState(ticketID: ticketID, phase: phase)
                        }
                    }
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    outputTextView(
                        outputText.isEmpty ? "No output captured for this phase yet." : outputText,
                        isRunning: liveOutput?.isRunning == true
                    )

                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchor)
                }
                .padding(14)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onAppear {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: liveOutputRevision) { _, _ in
                    guard liveOutput?.isRunning == true else {
                        return
                    }
                    scrollToBottom(using: proxy, animated: false)
                }
            }
        }
        .padding(18)
        .navigationTitle(windowTitle(ticket: ticket, phase: phase))
    }

    private func displayText(
        liveOutput: AppStore.LivePhaseOutput?,
        persistedState: TicketPhaseState?
    ) -> String {
        if let liveOutput {
            if liveOutput.combinedText.isEmpty == false {
                return liveOutput.combinedText
            }
            if liveOutput.isRunning {
                return "Waiting for process output…"
            }
        }

        let stdout = persistedState?.capturedOutput ?? ""
        let stderr = persistedState?.capturedError ?? ""

        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, true):
            return stdout
        case (true, false):
            return stderr
        case (false, false):
            return "\(stdout)\n\n[stderr]\n\(stderr)"
        case (true, true):
            return ""
        }
    }

    private func visibleDisplayText(
        liveOutput: AppStore.LivePhaseOutput?,
        persistedState: TicketPhaseState?
    ) -> String {
        let text = displayText(liveOutput: liveOutput, persistedState: persistedState)
        return text.liveOutputTail(maxCharacters: 12_000)
    }

    @ViewBuilder
    private func outputTextView(_ text: String, isRunning: Bool) -> some View {
        let outputText = Text(text)
            .font(.footnote.monospaced())
            .frame(maxWidth: .infinity, alignment: .topLeading)

        if isRunning {
            outputText
        } else {
            outputText.textSelection(.enabled)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    private func windowTitle(ticket: Ticket?, phase: TicketPhase) -> String {
        if let ticket {
            return "\(ticket.title) • \(phase.title) Output"
        }
        return "\(phase.title) Output"
    }

    private func processSummary(for phaseState: TicketPhaseState, liveOutput: AppStore.LivePhaseOutput?) -> String {
        if let pid = liveOutput?.processIdentifier {
            return "Harnessflow is actively attached to PID \(pid)."
        }
        if let ownedProcess = phaseState.ownedProcess {
            return "This phase has a recorded process PID \(ownedProcess.processIdentifier). Terminate will verify ownership before sending signals."
        }
        return ""
    }
}

private extension String {
    func liveOutputTail(maxCharacters: Int) -> String {
        guard count > maxCharacters else {
            return self
        }

        let startIndex = index(endIndex, offsetBy: -maxCharacters)
        return "[Showing latest \(maxCharacters.formatted()) characters of live output]\n\n" + self[startIndex...]
    }
}
