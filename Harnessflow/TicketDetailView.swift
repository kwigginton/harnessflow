import SwiftUI
import HarnessflowCore

struct TicketDetailView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var store: AppStore
    let summary: AppStore.BoardTicketSummary?
    let ticket: Ticket?
    @State private var promptDraft = ""
    @State private var expandedOutputPhases = Set<TicketPhase>()
    @State private var isLatestResultExpanded = false
    @State private var isRunHistoryExpanded = false
    @State private var selectedChoices: [String: String] = [:]
    @State private var freeformAnswers: [String: String] = [:]

    private var paneBackground: Color {
        Color(nsColor: .underPageBackgroundColor)
    }

    var body: some View {
        ZStack {
            paneBackground

            if let ticket {
                detail(for: ticket)
            } else if let summary {
                loadingDetail(for: summary)
            } else {
                ContentUnavailableView(
                    "Select a Ticket",
                    systemImage: "rectangle.stack",
                    description: Text("Choose a card from the board to edit its phase addendum, inspect outputs, or run the current phase.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func loadingDetail(for summary: AppStore.BoardTicketSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.title)
                        .font(.title2.weight(.semibold))

                    if summary.detailsPreview.isEmpty == false {
                        Text(summary.detailsPreview)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        PhaseLabel(phase: summary.column, font: .callout.weight(.semibold), iconSize: 20)
                        StatusBadge(state: summary.currentExecutionState)
                        Text("Model: \(store.settings.phaseModels.model(for: summary.column))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading ticket detail...")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                        PhaseLabel(phase: phase, font: .callout.weight(.semibold), iconSize: 20)
                        StatusBadge(state: phaseState.executionState)
                        Text("Model: \(store.settings.phaseModels.model(for: phase))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let questionSet = phaseState.pendingQuestions {
                    agentQuestionsSection(ticket: ticket, questionSet: questionSet)
                }

                GroupBox("Phase Addendum") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $promptDraft)
                            .font(.body.monospaced())
                            .frame(minHeight: 140)

                        HStack {
                            Button("Save Addendum") {
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
                            .disabled(phaseState.executionState == .awaitingInput)

                            Spacer()
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("Phase Outputs") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(TicketPhase.allCases) { outputPhase in
                            let outputState = ticket.phaseState(for: outputPhase)

                            DisclosureGroup(
                                isExpanded: outputBinding(for: outputPhase)
                            ) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let generatedAt = outputState.deliverableGeneratedAt {
                                        Text("Generated: \(generatedAt.formatted(date: .numeric, time: .shortened))")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    if outputState.executionState == .running {
                                        if outputState.ownedProcess != nil {
                                            Text(processSummary(for: outputState, liveOutput: store.liveOutput(for: ticket.id, phase: outputPhase)))
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)

                                            runningProcessActions(
                                                ticketID: ticket.id,
                                                phase: outputPhase,
                                                canTerminate: true
                                            )
                                        } else {
                                            Text("This running state has no recorded process ownership. It can be cleared, but not terminated from Harnessflow.")
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)

                                            legacyRunningStateActions(ticketID: ticket.id, phase: outputPhase)
                                        }
                                    }

                                    Button(outputState.executionState == .running ? "Open Live Output Window" : "Open Output Window") {
                                        openOutputWindow(ticketID: ticket.id, phase: outputPhase)
                                    }

                                    if outputState.deliverableMarkdown.isEmpty == false {
                                        OutputBlock(title: "Deliverable", text: outputState.deliverableMarkdown)
                                    } else {
                                        Text("No persisted deliverable for this phase yet.")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack(spacing: 10) {
                                    PhaseLabel(phase: outputPhase, font: .callout.weight(.semibold), iconSize: 18)
                                    StatusBadge(state: outputState.executionState)
                                    Spacer(minLength: 0)
                                    Button("Open") {
                                        openOutputWindow(ticketID: ticket.id, phase: outputPhase)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
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

                        if phaseState.capturedOutput.isEmpty && phaseState.capturedError.isEmpty {
                            Text("No execution result captured for this phase yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            DisclosureGroup("Captured Output", isExpanded: $isLatestResultExpanded) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if phaseState.capturedOutput.isEmpty == false {
                                        OutputBlock(title: "Output", text: phaseState.capturedOutput)
                                    }

                                    if phaseState.capturedError.isEmpty == false {
                                        OutputBlock(title: "Error", text: phaseState.capturedError)
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }

                        if phaseState.executionState == .running {
                            Divider()

                            if phaseState.ownedProcess != nil {
                                Text(processSummary(for: phaseState, liveOutput: store.liveOutput(for: ticket.id, phase: phase)))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                runningProcessActions(ticketID: ticket.id, phase: phase, canTerminate: true)
                            } else {
                                Text("This running state has no recorded process ownership. It can be cleared, but not terminated from Harnessflow.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                legacyRunningStateActions(ticketID: ticket.id, phase: phase)
                            }
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
                            DisclosureGroup("\(phaseState.runs.count) run\(phaseState.runs.count == 1 ? "" : "s")", isExpanded: $isRunHistoryExpanded) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(phaseState.runs.reversed()) { run in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack {
                                                Text(runStatusTitle(run))
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
                                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            promptDraft = phaseState.prompt
            resetAnswers(from: phaseState.pendingQuestions)
            expandedOutputPhases = []
            isLatestResultExpanded = false
            isRunHistoryExpanded = false
        }
        .onChange(of: ticket.id) { _, _ in
            promptDraft = ticket.phaseState(for: ticket.column).prompt
            resetAnswers(from: ticket.phaseState(for: ticket.column).pendingQuestions)
            expandedOutputPhases = []
            isLatestResultExpanded = false
            isRunHistoryExpanded = false
        }
        .onChange(of: phaseState.pendingQuestions?.id) { _, _ in
            resetAnswers(from: phaseState.pendingQuestions)
        }
        .onChange(of: phaseState.prompt) { _, _ in
            if phaseState.prompt != promptDraft, phaseState.executionState != .running {
                promptDraft = phaseState.prompt
            }
        }
    }

    @ViewBuilder
    private func agentQuestionsSection(ticket: Ticket, questionSet: AgentQuestionSet) -> some View {
        GroupBox("Agent Needs Answers") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(questionSet.questions) { question in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(question.prompt)
                            .font(.subheadline.weight(.semibold))

                        if question.choices.isEmpty == false {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(question.choices) { choice in
                                    Button {
                                        selectedChoices[question.id] = choice.id
                                    } label: {
                                        QuestionChoiceRow(
                                            choice: choice,
                                            isSelected: selectedChoices[question.id] == choice.id
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if question.allowsFreeform {
                            TextField("Answer", text: Binding(
                                get: { freeformAnswers[question.id] ?? "" },
                                set: { freeformAnswers[question.id] = $0 }
                            ), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...5)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    Button {
                        Task {
                            await store.submitAnswersAndContinue(ticketID: ticket.id, answers: answers(for: questionSet))
                        }
                    } label: {
                        Label("Submit Answers & Continue", systemImage: "arrowshape.turn.up.right.fill")
                    }
                    .disabled(ticket.phaseState(for: ticket.column).executionState == .running)
                    .disabled(hasMissingRequiredAnswers(in: questionSet))

                    Spacer()
                }
            }
            .padding(.top, 4)
        }
    }

    private func resetAnswers(from questionSet: AgentQuestionSet?) {
        selectedChoices = [:]
        freeformAnswers = [:]

        guard let questionSet else {
            return
        }

        for question in questionSet.questions {
            if let defaultChoiceID = question.defaultChoiceID {
                selectedChoices[question.id] = defaultChoiceID
            } else if question.choices.count == 1 {
                selectedChoices[question.id] = question.choices[0].id
            }
        }
    }

    private func answers(for questionSet: AgentQuestionSet) -> [AgentAnswer] {
        questionSet.questions.map { question in
            AgentAnswer(
                questionID: question.id,
                choiceID: selectedChoices[question.id],
                freeformText: freeformAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func hasMissingRequiredAnswers(in questionSet: AgentQuestionSet) -> Bool {
        questionSet.questions.contains { question in
            let hasChoice = question.choices.isEmpty || selectedChoices[question.id] != nil
            let freeformText = freeformAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let hasFreeform = question.allowsFreeform == false || freeformText.isEmpty == false
            return hasChoice == false || hasFreeform == false
        }
    }

    private func outputBinding(for phase: TicketPhase) -> Binding<Bool> {
        Binding(
            get: { expandedOutputPhases.contains(phase) },
            set: { isExpanded in
                if isExpanded {
                    expandedOutputPhases.insert(phase)
                } else {
                    expandedOutputPhases.remove(phase)
                }
            }
        )
    }

    private func openOutputWindow(ticketID: UUID, phase: TicketPhase) {
        openWindow(id: "phase-output", value: PhaseOutputWindowRoute(ticketID: ticketID, phase: phase))
    }

    @ViewBuilder
    private func runningProcessActions(ticketID: UUID, phase: TicketPhase, canTerminate: Bool) -> some View {
        HStack(spacing: 8) {
            if canTerminate {
                Button("Terminate Process") {
                    store.terminateOwnedProcess(ticketID: ticketID, phase: phase)
                }
            }

            if canTerminate {
                Button("Force Kill") {
                    store.terminateOwnedProcess(ticketID: ticketID, phase: phase, force: true)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func legacyRunningStateActions(ticketID: UUID, phase: TicketPhase) -> some View {
        HStack(spacing: 8) {
            Button("Clear Running State") {
                store.clearStuckRunningState(ticketID: ticketID, phase: phase)
            }
        }
        .buttonStyle(.bordered)
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

    private func runStatusTitle(_ run: PhaseRun) -> String {
        if run.success {
            return "Completed"
        }
        if AgentQuestionContract.extractQuestionSet(from: run.output) != nil {
            return "Awaiting Input"
        }
        return "Failed"
    }
}

private struct QuestionChoiceRow: View {
    let choice: AgentQuestionChoice
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label)
                if let description = choice.description, description.isEmpty == false {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct StatusBadge: View {
    let state: PhaseExecutionState

    private var color: Color {
        switch state {
        case .idle:
            .secondary
        case .running:
            .orange
        case .awaitingInput:
            .blue
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

    private var previewText: String {
        text.outputPreview(maxCharacters: 4_000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ScrollView {
                Text(previewText)
                    .font(.footnote.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 90, maxHeight: 180)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private extension String {
    func outputPreview(maxCharacters: Int) -> String {
        guard count > maxCharacters else {
            return self
        }

        let startIndex = index(endIndex, offsetBy: -maxCharacters)
        return "[Showing latest \(maxCharacters.formatted()) characters. Open the output window for more.]\n\n" + self[startIndex...]
    }
}
