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

    private var columns: [BoardColumn] {
        TicketPhase.allCases.map(BoardColumn.phase) + [.done]
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach(columns) { column in
                        PhaseColumnView(
                            column: column,
                            tickets: tickets(for: column)
                        )
                    }
                }
                .frame(minHeight: max(proxy.size.height - 40, 0), alignment: .topLeading)
                .padding(20)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tickets(for column: BoardColumn) -> [Ticket] {
        switch column {
        case let .phase(phase):
            return store.tickets.filter { $0.isDone == false && $0.column == phase }
        case .done:
            return store.tickets
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
                    Text("Drop tickets here")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 72)
                } else {
                    ForEach(tickets) { ticket in
                        TicketCardView(ticket: ticket)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(isTargeted ? 0.24 : 0.08), lineWidth: 1)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let dropPhase else {
                return false
            }
            guard let first = items.first, let id = UUID(uuidString: first) else {
                return false
            }
            return store.moveTicket(id: id, to: dropPhase)
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
    let ticket: Ticket

    private var currentState: TicketPhaseState {
        ticket.phaseState(for: ticket.column)
    }

    private var statusColor: Color {
        switch currentState.executionState {
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

    private var showsShiftButton: Bool {
        ticket.isDone == false && currentState.executionState == .completed
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
                        Text(currentState.executionState.displayTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor.opacity(0.14), in: Capsule())
                            .foregroundStyle(statusColor)

                        Spacer()

                        if showsShiftButton {
                            Button("Shift >") {
                                store.shiftTicketForward(id: ticket.id)
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
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(store.selectedTicketID == ticket.id ? Color.accentColor.opacity(0.15) : Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .draggable(ticket.id.uuidString)
    }
}
