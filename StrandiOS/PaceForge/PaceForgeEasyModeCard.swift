import SwiftUI
import StrandDesign

/// Easy mode on PaceForge Today: the active mode (level, summary, day N of M, the date it returns on,
/// whether it can be restored) and any proposal waiting for an answer. The athlete accepts a proposal here and
/// ends a running mode here (PaceForgeEasyModeActions.swift); starting one is the start card, shown when none is on.
struct PFEasyModeCard: View {
    let easy: PFEasyMode

    var body: some View {
        PFCard(title: "Easy mode", icon: "leaf", info: PFExplainerID.easyMode, trailing: {
            if let mode = easy.mode {
                PFChip(text: "Level \(mode.level)", color: StrandPalette.accent)
                    .accessibilityIdentifier("pf-easy-level")
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                if let mode = easy.mode { modeBlock(mode) }
                if !easy.pending.isEmpty { pendingBlock }
            }
        }
        .containerIdentifier("pf-easy-card")
    }

    // MARK: Active mode

    private func modeBlock(_ mode: PFEasyMode.Mode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode.label)
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .accessibilityIdentifier("pf-easy-label")
            if let summary = mode.summary { PFParagraph(summary) }
            if let day = mode.day, let total = mode.ofDays, total > 0 {
                ProgressView(value: min(max(Double(day) / Double(total), 0), 1))
                    .tint(StrandPalette.accent)
                    .accessibilityLabel("Day \(day) of \(total)")
            }
            HStack(spacing: 8) {
                if let text = mode.dayText { Text(text).font(StrandFont.caption.weight(.semibold)).foregroundStyle(StrandPalette.textSecondary) }
                if let returns = mode.returnsOn {
                    Text("Back to the plan \(PFFormat.dayTitle(returns))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                } else if let until = mode.until {
                    Text("Until \(PFFormat.dayTitle(until))")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .containerIdentifier("pf-easy-days")
            HStack(spacing: 8) {
                if let changed = mode.changedCount, changed > 0 {
                    Text(changed == 1 ? "1 session changed" : "\(changed) sessions changed")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                if mode.restorable {
                    PFChip(text: "Restorable", color: StrandPalette.textSecondary)
                        .accessibilityIdentifier("pf-easy-restorable")
                }
            }
            PFEasyModeEndButton()
        }
    }

    // MARK: Proposals

    private var pendingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Waiting for your answer").strandOverline()
            ForEach(easy.pending) { proposal in
                VStack(alignment: .leading, spacing: 4) {
                    Text(proposal.title)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail(proposal))
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    PFEasyModeAcceptButton(proposalID: proposal.proposalId)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
                .accessibilityElement(children: .combine)
                .containerIdentifier("pf-easy-pending-\(proposal.proposalId)")
            }
        }
    }

    private func detail(_ proposal: PFEasyMode.Proposal) -> String {
        var bits: [String] = []
        if let level = proposal.level { bits.append("Level \(level)") }
        if let days = proposal.days { bits.append(days == 1 ? "1 day" : "\(days) days") }
        if let until = proposal.until { bits.append("until \(PFFormat.dayTitle(until))") }
        return bits.joined(separator: " \u{00B7} ")
    }
}

/// The small chip at the top of Today while a mode is on.
struct PFEasyModeChip: View {
    let mode: PFEasyMode.Mode

    private var text: String {
        var text = "Easy mode \u{00B7} level \(mode.level)"
        if let day = mode.dayText { text += " \u{00B7} " + day.lowercased() }
        return text
    }

    var body: some View {
        HStack {
            PFChip(text: text, color: StrandPalette.accent)
                .accessibilityIdentifier("pf-easy-chip")
            Spacer(minLength: 0)
        }
    }
}

/// Small badges on a session row: marked by the active easy mode, and a thermometer on a hot day.
struct PFWorkoutBadges: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot

    static func hasAny(_ workout: PFWorkout, _ snapshot: PFSnapshot) -> Bool {
        let badges = PFWorkoutBadges(workout: workout, snapshot: snapshot)
        return badges.changedByEasyMode || badges.hotHeat != nil
    }

    private var changedByEasyMode: Bool {
        snapshot.easyMode?.mode?.changedSessionIds.contains(workout.id) == true
    }

    /// The heat of the activity this session was done as, when it was a hot one.
    private var hotHeat: PFHeat? {
        guard let heat = workout.activityId.flatMap({ snapshot.activities[$0]?.heat }), heat.isHot else { return nil }
        return heat
    }

    var body: some View {
        HStack(spacing: 10) {
            if changedByEasyMode {
                Label("Changed by easy mode", systemImage: "leaf")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityIdentifier("pf-easy-changed-\(workout.id)")
            }
            if let heat = hotHeat {
                Label(heat.tempC.map { "\(Safe.int($0))\u{00B0}" } ?? "Hot", systemImage: "thermometer.sun")
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .accessibilityLabel("Hot day")
                    .accessibilityIdentifier("pf-heat-glyph-\(workout.id)")
            }
        }
    }
}
