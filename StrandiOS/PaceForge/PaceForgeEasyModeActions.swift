import SwiftUI
import StrandDesign

// The actions on easy mode: start (Light / Reduce / Rest-ish for 3 to 14 days), accept what was proposed, end it. Jobs: PaceForgeEasyModeJobs.swift.

/// The Easy mode section of Training › Plan: the card while a mode is on or proposed, else the start card.
struct PFEasyModeSection: View {
    let easy: PFEasyMode

    var body: some View {
        if easy.isIdle {
            PFEasyModeStartCard()
        } else {
            PFEasyModeCard(easy: easy)
        }
    }
}

/// Not feeling 100 %? Pick how much to take off and for how many days; PaceForge files a proposal, which the card then shows with Accept.
struct PFEasyModeStartCard: View {
    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var level = PFEasyModeJobs.defaultLevel
    @State private var days = PFEasyModeJobs.defaultDays
    @State private var note: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        PFCard(String(localized: "Easy mode"), icon: "leaf", info: PFExplainerID.easyMode) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Not feeling 100 %? Pick how much to take off. PaceForge proposes it and you accept.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(PFEasyLevel.allCases, id: \.rawValue) { option in levelChip(option) }
                }
                Stepper(value: $days, in: PFEasyModeJobs.days) {
                    Text("For \(days) days")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                Button {
                    Task { await start() }
                } label: {
                    Text("Start easy mode")
                        .font(StrandFont.subhead.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(StrandPalette.accent)
                .disabled(isBusy)
                .accessibilityIdentifier("pf-easy-start")
                status
            }
        }
        .containerIdentifier("pf-easy-start-card")
    }

    private func levelChip(_ option: PFEasyLevel) -> some View {
        Button {
            level = option
        } label: {
            Text(Self.label(option))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(level == option ? StrandPalette.surfaceBase : StrandPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(level == option ? StrandPalette.accent : StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf-easy-level-\(option.rawValue)")
    }

    private static func label(_ option: PFEasyLevel) -> LocalizedStringKey {
        switch option {
        case .light: return "Light"
        case .reduce: return "Reduce"
        case .restish: return "Rest-ish"
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Working on it")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            if let note {
                Text(note)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func start() async {
        guard let inputs = PFJobInputs.easyMode(level: level, days: days) else { return }
        note = nil
        if case .success(let result) = await tracker.run(.easyMode, inputs: inputs) {
            note = PFEasyModeJobs.filedLine(result)
            await model.refresh()
        }
    }
}

/// Accept under a proposal waiting in the Easy mode card: the answer a proposal in Needs you takes, so the same code sends it.
struct PFEasyModeAcceptButton: View {
    let proposalID: String

    @EnvironmentObject private var model: PFModel
    @State private var isSending = false

    var body: some View {
        if let item = PFEasyModeJobs.item(forProposal: proposalID, in: model.snapshot?.needsYou ?? []) {
            Button {
                Task { await accept(item) }
            } label: {
                Text("Accept")
                    .font(StrandFont.subhead.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.accent)
            .disabled(isSending)
            .accessibilityIdentifier("pf-easy-accept-\(proposalID)")
        } else {
            Text("Accept it in Needs you at the top of Today.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private func accept(_ item: PFNeedsItem) async {
        guard let id = item.proposalID else { return }
        isSending = true
        await model.submitAnswer(.proposal(id: id, accept: true), for: item)
        isSending = false
    }
}

/// End easy mode now: the sessions still ahead and unedited are restored. Asks first.
struct PFEasyModeEndButton: View {
    @EnvironmentObject private var model: PFModel
    @StateObject private var tracker = PFJobTracker()
    @State private var asksToEnd = false

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("End easy mode", role: .destructive) { asksToEnd = true }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .confirmationDialog("End easy mode now? The sessions still ahead go back to the plan.",
                                    isPresented: $asksToEnd, titleVisibility: .visible) {
                    Button("End easy mode", role: .destructive) { Task { await end() } }
                }
                .accessibilityIdentifier("pf-easy-end")
            if case .failed(let message) = tracker.phase {
                Text(message)
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @MainActor private func end() async {
        if case .success = await tracker.run(.easyModeEnd, inputs: [:]) { await model.refresh() }
    }
}
