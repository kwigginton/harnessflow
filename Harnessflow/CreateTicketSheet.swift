import SwiftUI

struct CreateTicketSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var detailsText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Ticket")
                .font(.title3.weight(.semibold))

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(.subheadline.weight(.medium))
                TextEditor(text: $detailsText)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()

                Button("Cancel", role: .cancel) {
                    isPresented = false
                }

                Button("Create") {
                    store.createTicket(title: title, detailsText: detailsText)
                    if store.errorMessage == nil {
                        isPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

