import SwiftUI
import HarnessflowCore

private enum BoardColumn: Identifiable {
    case phase(TicketPhase)
    case done

    var id: String {
        switch self {
        case let .phase(phase):
            "phase-\(phase.rawValue)"
        case .done:
            "done"
        }
    }

    var title: String {
        switch self {
        case let .phase(phase):
            phase.title
        case .done:
            "Done"
        }
    }
}

struct BoardView: View {
    @EnvironmentObject private var store: AppStore
    @State private var ticketProject: ProjectRecord?
    @State private var removalProject: ProjectRecord?

    private var columns: [BoardColumn] {
        TicketPhase.allCases.map(BoardColumn.phase) + [.done]
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(store.directoryBoardRows) { row in
                        DirectoryBoardRowView(
                            row: row,
                            columns: columns,
                            availableWidth: proxy.size.width,
                            selection: store.selection,
                            onCreateTicket: {
                                ticketProject = row.project
                            },
                            onRemoveDirectory: {
                                removalProject = row.project
                            }
                        )
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $ticketProject) { project in
            CreateTicketSheet(isPresented: ticketSheetBinding, project: project)
                .environmentObject(store)
        }
        .confirmationDialog(
            "Remove Working Directory Row?",
            isPresented: removalDialogBinding,
            titleVisibility: .visible
        ) {
            Button("Remove Row", role: .destructive) {
                if let removalProject {
                    store.removeDirectoryRow(projectID: removalProject.id)
                }
                removalProject = nil
            }

            Button("Cancel", role: .cancel) {
                removalProject = nil
            }
        } message: {
            Text("The row will be hidden, but its tickets stay in the local database. Add the same directory again to restore them.")
        }
    }

    private var ticketSheetBinding: Binding<Bool> {
        Binding(
            get: { ticketProject != nil },
            set: { isPresented in
                if isPresented == false {
                    ticketProject = nil
                }
            }
        )
    }

    private var removalDialogBinding: Binding<Bool> {
        Binding(
            get: { removalProject != nil },
            set: { isPresented in
                if isPresented == false {
                    removalProject = nil
                }
            }
        )
    }
}

private struct DirectoryBoardRowView: View {
    let row: AppStore.DirectoryBoardRow
    let columns: [BoardColumn]
    let availableWidth: CGFloat
    let selection: AppStore.TicketSelectionState
    let onCreateTicket: () -> Void
    let onRemoveDirectory: () -> Void

    private var displayName: String {
        if row.project.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return row.project.name
        }

        let lastPathComponent = URL(fileURLWithPath: row.project.workingDirectory).lastPathComponent
        return lastPathComponent.isEmpty ? "Working Directory" : lastPathComponent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(displayName)
                            .font(.headline)
                            .lineLimit(1)
                    }

                    Text(row.project.workingDirectory)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 12)

                Text("\(row.ticketCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button(action: onCreateTicket) {
                    Label("Create Ticket", systemImage: "plus.rectangle.on.rectangle")
                }
                .help("Create Ticket in \(displayName)")

                Button(role: .destructive, action: onRemoveDirectory) {
                    Label("Remove", systemImage: "trash")
                }
                .help("Remove Working Directory Row")
            }
            .padding(.horizontal, 2)

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(columns) { column in
                        PhaseColumnView(
                            projectID: row.project.id,
                            column: column,
                            tickets: tickets(for: column),
                            selection: selection
                        )
                    }
                }
                .padding(.bottom, 2)
                .frame(minWidth: max(availableWidth - 40, 0), alignment: .topLeading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .underPageBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func tickets(for column: BoardColumn) -> [AppStore.BoardTicketSummary] {
        switch column {
        case let .phase(phase):
            return row.tickets(for: phase)
        case .done:
            return row.doneTickets
        }
    }
}

private struct PhaseColumnView: View {
    @EnvironmentObject private var store: AppStore
    let projectID: UUID
    let column: BoardColumn
    let tickets: [AppStore.BoardTicketSummary]
    @ObservedObject var selection: AppStore.TicketSelectionState
    @State private var isTargeted = false

    private var dropPhase: TicketPhase? {
        if case let .phase(phase) = column {
            return phase
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                headerLabel
                Spacer()
                Text("\(tickets.count)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                if tickets.isEmpty {
                    Text(dropPhase == nil ? "Completed tickets" : "Drop tickets here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(tickets) { ticket in
                        TicketCardView(
                            ticket: ticket,
                            isSelected: selection.selectedTicketID == ticket.id,
                            onSelect: {
                                store.selectTicket(ticket.id)
                            },
                            onComplete: {
                                store.completeTicket(id: ticket.id, projectID: projectID)
                            },
                            onShiftForward: {
                                store.shiftTicketForward(id: ticket.id, projectID: projectID)
                            }
                        )
                        .equatable()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(isTargeted ? 0.24 : 0.08), lineWidth: 1)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let dropPhase else {
                return false
            }
            guard let first = items.first, let id = UUID(uuidString: first) else {
                return false
            }
            return store.moveTicket(id: id, to: dropPhase, projectID: projectID)
        } isTargeted: { targeted in
            isTargeted = dropPhase == nil ? false : targeted
        }
    }

    @ViewBuilder
    private var headerLabel: some View {
        switch column {
        case let .phase(phase):
            PhaseLabel(phase: phase, font: .headline)
        case .done:
            Label("Done", systemImage: "checkmark.circle")
                .font(.headline)
        }
    }
}

@MainActor
private struct TicketCardView: View, @preconcurrency Equatable {
    let ticket: AppStore.BoardTicketSummary
    let isSelected: Bool
    let onSelect: () -> Void
    let onComplete: () -> Void
    let onShiftForward: () -> Void

    static func == (lhs: TicketCardView, rhs: TicketCardView) -> Bool {
        lhs.ticket == rhs.ticket && lhs.isSelected == rhs.isSelected
    }

    private var isWaitingForFinalAdjustments: Bool {
        ticket.needsFinalAdjustments && ticket.currentExecutionState == .completed
    }

    private var statusColor: Color {
        if isWaitingForFinalAdjustments {
            return .orange
        }

        switch ticket.currentExecutionState {
        case .idle:
            return .secondary
        case .running:
            return .orange
        case .awaitingInput:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusTitle: String {
        isWaitingForFinalAdjustments ? "Final Adjustments" : ticket.currentExecutionState.displayTitle
    }

    private var showsShiftButton: Bool {
        ticket.isDone == false && ticket.currentExecutionState == .completed
    }

    private var showsCompleteButton: Bool {
        ticket.isDone == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onSelect()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ticket.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if ticket.detailsPreview.isEmpty == false {
                        Text(ticket.detailsPreview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack {
                        Text(statusTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(statusColor)

                        Spacer()

                        if showsCompleteButton {
                            Button {
                                onComplete()
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.body)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Mark Completed")
                        }

                        if showsShiftButton {
                            Button("Shift >") {
                                onShiftForward()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        } else if ticket.currentExecutionState == .failed {
                            Image(systemName: "exclamationmark.circle")
                                .font(.body)
                                .frame(width: 16, height: 16)
                                .foregroundStyle(.red)
                                .help("Phase Failed")
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .draggable(ticket.id.uuidString)
    }
}
