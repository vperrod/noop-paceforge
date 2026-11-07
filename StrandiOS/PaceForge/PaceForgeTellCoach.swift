import SwiftUI
import StrandDesign

/// "Tell the coach": an order in plain words (move my long run to Sunday, I'm sick, waist 92) that PaceForge's coach turns into plan
/// edits, a niggle, an easy week or a tape entry (`coach`, a slow job: half a minute to a few minutes). Apart from the chat, which
/// stays for questions. Its changes are applied like an Accept, so there is no review step; what it asks to be looked at is shown as
/// a plain list.
struct PFTellCoachCard: View {
    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var draft = ""
    @State private var reply: String?
    @State private var filed: [String] = []

    private static let bullet = "\u{2022} "

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        PFCard(String(localized: "Tell the coach"), icon: "pencil") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Give an order in plain words, like move my long run to Sunday. To ask a question, use the chat above.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("What should change?", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
                    .accessibilityIdentifier("pf-tell-coach-input")
                Button {
                    Task { await send() }
                } label: {
                    Text("Send")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(isBusy || PFJobInputs.coach(draft) == nil)
                .accessibilityIdentifier("pf-tell-coach-send")
                status
            }
        }
        .containerIdentifier("pf-tell-coach")
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("Working on it. This can take a few minutes.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            outcome
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var outcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply {
                Text(reply)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-tell-coach-reply")
            } else {
                Text("Done.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if !filed.isEmpty {
                Text("The coach filed these for you to look at:")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                ForEach(filed, id: \.self) { title in
                    Text(Self.bullet + title)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @MainActor private func send() async {
        guard let inputs = PFJobInputs.coach(draft) else { return }
        let previous = model.snapshot?.coach.chat.last(where: { $0.role == "coach" })?.ts
        let before = model.snapshot?.needsYou ?? []
        reply = nil
        filed = []
        guard case .success = await tracker.run(.coach, inputs: inputs) else { return }
        draft = ""
        await model.refresh()
        reply = PFCoachInstruction.reply(in: model.snapshot?.coach.chat ?? [], after: previous)
        filed = PFCoachInstruction.newProposals(before: before, after: model.snapshot?.needsYou ?? [])
    }
}
