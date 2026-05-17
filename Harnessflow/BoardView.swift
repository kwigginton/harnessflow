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

                Text("\(row.tickets.count)")
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
                            tickets: tickets(for: column)
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

    private func tickets(for column: BoardColumn) -> [Ticket] {
        switch column {
        case let .phase(phase):
            return row.tickets.filter { $0.isDone == false && $0.column == phase }
        case .done:
            return row.tickets
                .filter(\.isDone)
                .sorted { lhs, rhs in
                    let lhsDate = lhs.completedAt ?? lhs.updatedAt
                    let rhsDate = rhs.completedAt ?? rhs.updatedAt
                    return lhsDate > rhsDate
                }
        }
    }
}

private struct PhaseColumnView: View {
    @EnvironmentObject private var store: AppStore
    let projectID: UUID
    let column: BoardColumn
    let tickets: [Ticket]
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
                        TicketCardView(projectID: projectID, ticket: ticket)
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

private struct TicketCardView: View {
    @EnvironmentObject private var store: AppStore
    let projectID: UUID
    let ticket: Ticket

    private var currentState: TicketPhaseState {
        ticket.phaseState(for: ticket.column)
    }

    private var statusColor: Color {
        if currentState.needsFinalAdjustments {
            return .orange
        }

        switch currentState.executionState {
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
        currentState.needsFinalAdjustments ? "Final Adjustments" : currentState.executionState.displayTitle
    }

    private var showsShiftButton: Bool {
        ticket.isDone == false && currentState.executionState == .completed
    }

    private var showsCompleteButton: Bool {
        ticket.isDone == false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                store.selectTicket(ticket.id)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(ticket.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if ticket.detailsText.isEmpty == false {
                        Text(ticket.detailsText)
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
                                store.completeTicket(id: ticket.id, projectID: projectID)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .help("Mark Completed")
                        }

                        if showsShiftButton {
                            Button("Shift >") {
                                store.shiftTicketForward(id: ticket.id, projectID: projectID)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        } else if currentState.executionState == .idle || currentState.executionState == .failed {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundStyle(currentState.executionState == .failed ? .red : .secondary)
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(store.selectedTicketID == ticket.id ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
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
