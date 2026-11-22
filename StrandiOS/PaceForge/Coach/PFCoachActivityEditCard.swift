import SwiftUI
import StrandDesign

// The card under a Coach bubble that carries `activity_edit: {proposal_id}`: the Coach prepared an edit of a recording from the chat. The server
// stored it as a PENDING proposal and applied nothing; this card reads the proposal from `GET api/activity-edits` and opens the existing edit
// sheet (PFActivityEditSheet), where Confirm and "Not now" are the only way it changes anything. The wording is in PaceForgeActivityEdits.swift.

@MainActor struct PFCoachActivityEditCard: View {
    let proposalID: String

    @State private var proposal: PFEditProposal?
    @State private var didLoad = false
    @State private var isOpen = false

    private var target: PFEditTarget? { proposal.flatMap { PFActivityEdits.target(for: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PFActivityEdits.cardTitle(isPending: proposal?.isPending ?? true))
                .font(StrandFont.caption.weight(.semibold))
                .foregroundStyle(StrandPalette.textSecondary)
            if let proposal {
                Text(proposal.spec.summary)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let status = PFActivityEdits.cardStatus(state: proposal.state) {
                    Text(status)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if target != nil {
                    PFWeekButton529(title: "Review the edit", isProminent: true, identifier: "pf-coach-edit-review") { isOpen = true }
                }
            } else if didLoad {
                Text("The edit could not be loaded.")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                PFWeekButton529(title: "Try again", identifier: "pf-coach-edit-retry") { Task { await load() } }
            } else {
                ProgressView()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
        .containerIdentifier("pf-coach-edit-\(proposalID)")
        .sheet(isPresented: $isOpen, onDismiss: { Task { await load() } }) {
            if let target {
                PFActivityEditSheet(activityID: target.activityID, name: target.name, type: target.type, durationS: target.durationS, others: [])
            }
        }
        .task(id: proposalID) { await load() }
    }

    /// The proposal as the server holds it now; a failed read keeps what is shown and offers a retry when nothing is.
    @MainActor private func load() async {
        let data = await PFAPI.fetchOptional("api/activity-edits")
        if let found = PFActivityEdits.parse(data).proposals.first(where: { $0.id == proposalID }) { proposal = found }
        didLoad = true
    }
}
