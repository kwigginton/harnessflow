import SwiftUI
import HarnessflowCore

struct PhaseOutputPane: View {
    @EnvironmentObject private var store: AppStore

    let ticket: Ticket?
    let ticketID: UUID
    let phase: TicketPhase
    var showsTicketTitle = true
    var cornerRadius: CGFloat = 14
    var maxVisibleCharacters = 12_000

    private let bottomAnchor = "phase-output-bottom"

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            pane(now: timeline.date)
        }
    }

    @ViewBuilder
    private func pane(now: Date) -> some View {
        let liveOutput = store.liveOutput(for: ticketID, phase: phase)
        let persistedState = ticket?.phaseState(for: phase)
        let outputText = visibleDisplayText(liveOutput: liveOutput, persistedState: persistedState, now: now)
        let liveOutputRevision = liveOutput?.lastUpdatedAt

        VStack(alignment: .leading, spacing: 12) {
            header(liveOutput: liveOutput, persistedState: persistedState, now: now)

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
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
    }

    @ViewBuilder
    private func header(liveOutput: AppStore.LivePhaseOutput?, persistedState: TicketPhaseState?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsTicketTitle {
                Text(ticket?.title ?? "Ticket")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
            }

            HStack(spacing: 10) {
                PhaseLabel(phase: phase, font: .callout.weight(.semibold), iconSize: 18)

                if let liveOutput {
                    StatusBadge(state: liveOutput.isRunning ? .running : (persistedState?.executionState ?? .idle))
                    Text(liveProcessLabel(liveOutput))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)

                    Text("Elapsed \(elapsedText(from: liveOutput.startedAt, to: liveOutput.isRunning ? now : liveOutput.lastUpdatedAt))")
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

            if let liveOutput {
                Text("\(liveOutput.providerKind.title) | \(liveOutput.model) | \(liveOutput.origin.displayTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if persistedState?.executionState == .running {
                runningControls(persistedState: persistedState, liveOutput: liveOutput)
            }
        }
    }

    @ViewBuilder
    private func runningControls(persistedState: TicketPhaseState?, liveOutput: AppStore.LivePhaseOutput?) -> some View {
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

    private func displayText(
        liveOutput: AppStore.LivePhaseOutput?,
        persistedState: TicketPhaseState?,
        now: Date
    ) -> String {
        if let liveOutput {
            if liveOutput.combinedText.isEmpty == false {
                return liveOutput.combinedText
            }
            if liveOutput.isRunning {
                return runningPlaceholder(for: liveOutput, now: now)
            }
        }

        let stdout = persistedState?.capturedOutput ?? ""
        let stderr = persistedState?.capturedError ?? ""

        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, true):
            return stdout
        case (true, false):
            return "[stderr]\n" + stderr
        case (false, false):
            return stdout + (stdout.hasSuffix("\n") ? "" : "\n") + "\n[stderr]\n" + stderr
        case (true, true):
            return ""
        }
    }

    private func visibleDisplayText(
        liveOutput: AppStore.LivePhaseOutput?,
        persistedState: TicketPhaseState?,
        now: Date
    ) -> String {
        displayText(liveOutput: liveOutput, persistedState: persistedState, now: now)
            .liveOutputTail(maxCharacters: maxVisibleCharacters)
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

    private func processSummary(for phaseState: TicketPhaseState, liveOutput: AppStore.LivePhaseOutput?) -> String {
        if let pid = liveOutput?.processIdentifier {
            return "Harnessflow is actively attached to PID \(pid)."
        }
        if let ownedProcess = phaseState.ownedProcess {
            return "This phase has a recorded process PID \(ownedProcess.processIdentifier). Terminate will verify ownership before sending signals."
        }
        return ""
    }

    private func runningPlaceholder(for liveOutput: AppStore.LivePhaseOutput, now: Date) -> String {
        let provider = liveOutput.providerKind.title
        let process = liveProcessLabel(liveOutput)
        let outputStatus = liveOutput.providerKind == .claude
            ? "Claude is running but has not emitted output yet."
            : "The agent process is running but has not emitted output yet."

        return """
        \(outputStatus)

        Provider: \(provider)
        Model: \(liveOutput.model)
        Origin: \(liveOutput.origin.displayTitle)
        Process: \(process)
        Elapsed: \(elapsedText(from: liveOutput.startedAt, to: now))
        Started: \(liveOutput.startedAt.formatted(date: .numeric, time: .standard))
        """
    }

    private func liveProcessLabel(_ liveOutput: AppStore.LivePhaseOutput) -> String {
        liveOutput.processIdentifier.map { "PID \($0)" }
            ?? (liveOutput.isRunning ? "Launching..." : "Detached")
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(remainingSeconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }
}

extension String {
    func liveOutputTail(maxCharacters: Int) -> String {
        guard count > maxCharacters else {
            return self
        }

        let startIndex = index(endIndex, offsetBy: -maxCharacters)
        return "[Showing latest \(maxCharacters.formatted()) characters of live output]\n\n" + self[startIndex...]
    }
}
