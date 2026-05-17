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

        PhaseOutputPane(ticket: ticket, ticketID: ticketID, phase: phase)
        .padding(18)
        .navigationTitle(windowTitle(ticket: ticket, phase: phase))
    }

    private func windowTitle(ticket: Ticket?, phase: TicketPhase) -> String {
        if let ticket {
            return "\(ticket.title) • \(phase.title) Output"
        }
        return "\(phase.title) Output"
    }
}
