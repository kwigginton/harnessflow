import SwiftUI
import HarnessflowCore

extension TicketPhase {
    var iconAssetName: String {
        switch self {
        case .research:
            "ResearchPhase"
        case .plan:
            "PlanPhase"
        case .implement:
            "ImplementPhase"
        case .review:
            "ReviewPhase"
        }
    }
}

struct PhaseIcon: View {
    let phase: TicketPhase
    var size: CGFloat = 18

    var body: some View {
        Image(phase.iconAssetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PhaseLabel: View {
    let phase: TicketPhase
    var font: Font = .body
    var iconSize: CGFloat = 18
    var spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: spacing) {
            PhaseIcon(phase: phase, size: iconSize)
            Text(phase.title)
        }
        .font(font)
    }
}
