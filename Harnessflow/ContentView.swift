import SwiftUI
import HarnessflowCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isShowingCreateSheet = false

    var body: some View {
        HSplitView {
            BoardView()
                .frame(minWidth: 760, idealWidth: 920)

            TicketDetailView(ticket: store.selectedTicket)
                .frame(minWidth: 360, idealWidth: 420)
        }
        .navigationTitle("Harnessflow")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Label("Create", systemImage: "plus")
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateTicketSheet(isPresented: $isShowingCreateSheet)
                .environmentObject(store)
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { newValue in
                    if newValue == false {
                        store.clearError()
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    store.clearError()
                }
            },
            message: {
                Text(store.errorMessage ?? "")
            }
        )
    }
}

