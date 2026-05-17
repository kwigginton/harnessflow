import SwiftUI
import HarnessflowCore

struct TicketDetailWindowRoute: Hashable, Codable {
    let ticketID: UUID
}

struct TicketDetailWindowView: View {
    @EnvironmentObject private var store: AppStore

    let route: TicketDetailWindowRoute?
    @State private var selectedOutputPhase: TicketPhase = .research
    @State private var isOutputPhaseUserSelected = false

    var body: some View {
        Group {
            if let route, let ticket = store.ticket(withID: route.ticketID) {
                detailWindow(for: ticket)
            } else {
                ContentUnavailableView(
                    "Ticket Unavailable",
                    systemImage: "rectangle.stack.badge.xmark",
                    description: Text("The requested ticket could not be opened.")
                )
            }
        }
        .frame(minWidth: 980, minHeight: 640)
    }

    private func detailWindow(for ticket: Ticket) -> some View {
        PersistentHSplitView(
            autosaveKey: "ticket-detail-window.split.trailingFraction",
            defaultTrailingFraction: 0.36,
            minLeadingWidth: 520,
            minTrailingWidth: 360
        ) {
            TicketDetailView(summary: nil, ticket: ticket, isHeaderEditable: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } trailing: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Live Output")
                        .font(.headline)

                    Spacer()

                    Picker("Phase", selection: outputPhaseSelection) {
                        ForEach(TicketPhase.allCases) { phase in
                            Text(phase.title).tag(phase)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)
                }

                PhaseOutputPane(
                    ticket: ticket,
                    ticketID: ticket.id,
                    phase: selectedOutputPhase,
                    showsTicketTitle: false,
                    cornerRadius: 8,
                    maxVisibleCharacters: 12_000
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .navigationTitle(ticket.title)
        .onAppear {
            selectedOutputPhase = ticket.column
        }
        .onChange(of: ticket.id) { _, _ in
            isOutputPhaseUserSelected = false
            selectedOutputPhase = ticket.column
        }
        .onChange(of: ticket.column) { _, newColumn in
            guard isOutputPhaseUserSelected == false else {
                return
            }
            selectedOutputPhase = newColumn
        }
    }

    private var outputPhaseSelection: Binding<TicketPhase> {
        Binding(
            get: {
                selectedOutputPhase
            },
            set: { newValue in
                isOutputPhaseUserSelected = true
                selectedOutputPhase = newValue
            }
        )
    }
}
