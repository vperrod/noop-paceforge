import SwiftUI
import StrandDesign

// "Insights v2" screens: the cards on Insights, the Next best action card on Today and the detail screen every card
// opens. Every screen says what the number means and what to do about it (status chip, meaning, actions with their
// why and effort, the data note), and shows an honest "not enough data" state when the server has nothing to say.
// The parsing and the wording rules are in PaceForgeInsightsV2.swift (unit-tested); the charts for each item are in
// PaceForgeInsightsV2Detail.swift. Everything comes from insights-v2.json and the app only reads it.

// MARK: - Opening an insight

private struct PFOpenInsightKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens the detail screen of an insight by id; set once by the PaceForge tab.
    var pfOpenInsight: (String) -> Void {
        get { self[PFOpenInsightKey.self] }
        set { self[PFOpenInsightKey.self] = newValue }
    }
}

extension Notification.Name {
    static let pfOpenInsight = Notification.Name("noop.paceforge.openInsight")
}

/// `noop://paceforge/insights/power-curve` and the other items. Held as `pending` until the tab exists, so a cold
/// launch still lands on it.
@MainActor
enum PFInsightLink {
    static var pending: String?

    static func open(_ id: String) {
        pending = id
        NotificationCenter.default.post(name: .pfOpenInsight, object: nil)
    }

    /// The id of the waiting request, once.
    static func consume() -> String? {
        defer { pending = nil }
        return pending
    }
}

/// The insight a sheet shows.
struct PFInsightRoute: Identifiable, Equatable {
    let id: String
}

// MARK: - Look

enum PFInsightColor {
    static func color(for tone: PFInsightTone) -> Color {
        switch tone {
        case .positive: return PFColor.positive
        case .neutral: return StrandPalette.accent
        case .caution: return PFColor.warning
        case .unknown: return StrandPalette.textTertiary
        }
    }
}

enum PFInsightIcon {
    static func symbol(_ id: String) -> String {
        switch id {
        case PFInsightID.powerCurve: return "bolt.fill"
        case PFInsightID.raceCountdown: return "flag.checkered"
        case PFInsightID.weightGoal: return "scalemass"
        case PFInsightID.efficiency: return "speedometer"
        case PFInsightID.sleep: return "bed.double.fill"
        case PFInsightID.nextBestAction: return "arrow.forward.circle.fill"
        default: return "lightbulb"
        }
    }
}

struct PFInsightStatusChip: View {
    let item: PFInsightItem

    var body: some View {
        PFChip(text: item.chipText, color: PFInsightColor.color(for: item.tone))
            .accessibilityIdentifier("pf-insight-status-\(item.id)")
    }
}

/// A short "Not enough data yet" box inside a card: what is missing and why, in the server's words where it has them.
struct PFInsufficient: View {
    let title: String
    let text: String
    var identifier: String = "pf-insight-insufficient"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                PFParagraph(text)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }
}

/// A label on the left, a figure on the right and an optional caption under the label.
struct PFInsightRow: View {
    let label: String
    let value: String
    var caption: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                if let caption {
                    PFParagraph(caption)
                }
            }
            Spacer(minLength: 8)
            Text(value)
                .font(StrandFont.rounded(20))
                .foregroundStyle(StrandPalette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Actions

/// One concrete next step: what to do, why (his own numbers), what it costs and how much it should move.
struct PFInsightActionRow: View {
    let action: PFInsightAction
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hiding.text(action.text))
                .font(StrandFont.subhead.weight(.semibold))
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let why = action.why { PFLabeled(label: "Why", text: why) }
            HStack(spacing: 8) {
                if let effort = action.effort {
                    PFChip(text: effort.chipText, color: effort.isFree ? PFColor.positive : StrandPalette.accent)
                        .accessibilityIdentifier("pf-insight-effort-\(action.id)")
                }
                if let impact = action.impactText {
                    PFChip(text: impact, color: StrandPalette.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pf-insight-action-\(action.id)")
    }
}

struct PFInsightActionsCard: View {
    let item: PFInsightItem

    var body: some View {
        PFCard("What to do", icon: "checkmark.circle") {
            VStack(alignment: .leading, spacing: 14) {
                if item.actions.isEmpty {
                    PFParagraph("Nothing to change right now.")
                        .accessibilityIdentifier("pf-insight-no-actions")
                }
                ForEach(item.actions) { action in
                    PFInsightActionRow(action: action)
                    if action.id != item.actions.last?.id { Divider().overlay(StrandPalette.hairline) }
                }
            }
        }
        .containerIdentifier("pf-insight-actions-\(item.id)")
    }
}

// MARK: - Cards in the lists

/// One item on the Insights tab: status, the leading figure, the meaning and the first thing to do. Opens the detail.
struct PFInsightCard: View {
    let item: PFInsightItem
    @Environment(\.pfOpenInsight) private var openInsight
    private let hiding = PFHiding()

    private var hidden: Bool { item.hideKind.map(hiding.hides) ?? false }

    private var accessibilityText: String {
        var parts = [item.title, item.chipText]
        if let headline = item.headline { parts.append("\(hidden ? PFRedact.placeholder : headline.value) \(headline.caption)") }
        if let text = item.summaryText { parts.append(hiding.text(text)) }
        if let action = item.actions.first { parts.append("Next: " + hiding.text(action.text)) }
        return parts.joined(separator: ". ")
    }

    var body: some View {
        Button { openInsight(item.id) } label: {
            PFCard(title: item.title, icon: PFInsightIcon.symbol(item.id), trailing: {
                PFInsightStatusChip(item: item)
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    if let headline = item.headline {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(hidden ? PFRedact.placeholder : headline.value)
                                .font(StrandFont.rounded(30))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(headline.caption)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let text = item.summaryText {
                        Text(hiding.text(text))
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    if let action = item.actions.first {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(StrandPalette.accent)
                            Text(hiding.text(action.text))
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    HStack(spacing: 4) {
                        Text(item.available ? "See the detail" : "See why")
                            .font(StrandFont.caption.weight(.semibold))
                            .foregroundStyle(StrandPalette.accent)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens what it means and what to do")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("pf-insight-card-\(item.id)")
    }
}

/// The cards of every item the server sent (the next best action lives on Today).
struct PFInsightsV2Section: View {
    let doc: PFInsightsV2

    var body: some View {
        let cards = doc.insightCards
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(cards) { PFInsightCard(item: $0) }
            }
            .containerIdentifier("pf-insights-v2")
        }
    }
}

/// The Next best action card on Today: the one thing to do first, why, what it costs. Tapping opens the other options.
struct PFNextActionCard: View {
    let item: PFInsightItem
    @Environment(\.pfOpenInsight) private var openInsight
    private let hiding = PFHiding()

    /// An insight-style card: the action in the gradient frame, the chips under it and the link that opens the
    /// other options. Same content and the same tap as before.
    var body: some View {
        Button { openInsight(item.id) } label: {
            InsightCardFrame {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: PFInsightIcon.symbol(item.id))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                    Text("Next best action")
                        .lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                    Spacer(minLength: 8)
                    PFInsightStatusChip(item: item)
                }
                if let action = item.actions.first {
                    Text(hiding.text(action.text))
                        .font(LookFont.text(15.5, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let why = action.why {
                        Text(hiding.text(why))
                            .font(LookFont.text(14.5, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                    }
                    HStack(spacing: 8) {
                        if let effort = action.effort {
                            PFChip(text: effort.chipText, color: effort.isFree ? PFColor.positive : StrandPalette.accent)
                        }
                        if let impact = action.impactText {
                            PFChip(text: impact, color: StrandPalette.textTertiary)
                        }
                        Spacer(minLength: 4)
                    }
                    InsightLink("See the other options")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the other options and how they are ranked")
        .accessibilityIdentifier("pf-next-action-card")
    }
}

// MARK: - The detail screen

struct PFInsightDetailView: View {
    let item: PFInsightItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PFRevealBar()
                    header
                    if item.available {
                        meaningCard
                        PFInsightActionsCard(item: item)
                        metricDetail
                        noteCard
                    } else {
                        PFCard("Not enough data yet", icon: "hourglass") {
                            VStack(alignment: .leading, spacing: 10) {
                                if let text = item.meaning ?? item.status.reason { PFParagraph(text) }
                                if let note = item.dataNote, note != item.meaning { PFParagraph(note) }
                            }
                        }
                        .containerIdentifier("pf-insight-unavailable")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-insight-done")
                }
            }
        }
        .containerIdentifier("pf-insight-\(item.id)")
    }

    /// The status chip, how sure the server is, and the rule that produced the label.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PFInsightStatusChip(item: item)
                if let confidence = item.confidenceText {
                    PFChip(text: confidence, color: StrandPalette.textTertiary)
                        .accessibilityIdentifier("pf-insight-confidence")
                }
            }
            if item.available, item.status.label == nil, let reason = item.status.reason {
                PFParagraph(reason)
                    .accessibilityIdentifier("pf-insight-status-reason")
            }
            if let threshold = item.status.threshold, item.available {
                Text("How it is rated: \(threshold)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-insight-threshold")
            }
        }
    }

    @ViewBuilder private var meaningCard: some View {
        if let meaning = item.meaning {
            PFCard("What this means", icon: "text.alignleft") {
                PFParagraph(meaning)
                    .accessibilityIdentifier("pf-insight-meaning")
            }
        }
    }

    @ViewBuilder private var noteCard: some View {
        if let note = item.dataNote {
            PFCard("About this data", icon: "info.circle") {
                PFParagraph(note)
                    .accessibilityIdentifier("pf-insight-data-note")
            }
        }
    }

    @ViewBuilder private var metricDetail: some View {
        if let power = item.power {
            PFPowerCurveDetail(item: item, power: power)
        } else if let race = item.race {
            PFRaceCountdownDetail(item: item, race: race)
        } else if let weight = item.weight {
            PFWeightGoalDetail(item: item, weight: weight)
        } else if let efficiency = item.efficiency {
            PFEfficiencyDetail(item: item, efficiency: efficiency)
        } else if let sleep = item.sleep {
            PFSleepDetail(item: item, sleep: sleep)
        } else if let next = item.next {
            PFNextActionDetail(next: next)
        }
    }
}

// MARK: - Next best action: the other options

struct PFNextActionDetail: View {
    let next: PFNextActionMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            whyCard
            if !next.runnerUps.isEmpty { optionsCard }
            rankingCard
        }
    }

    @ViewBuilder private var whyCard: some View {
        if let chosen = next.chosen {
            PFCard("Why this one", icon: "arrow.up.right") {
                VStack(alignment: .leading, spacing: 10) {
                    if let reason = chosen.reason {
                        PFParagraph(reason)
                            .accessibilityIdentifier("pf-nba-reason")
                    }
                    if !chosen.alsoSuggestedBy.isEmpty {
                        PFParagraph("Also pointed to by " + chosen.alsoSuggestedBy.map { PFFormat.words($0) }.joined(separator: ", ") + ".")
                    }
                    if let word = next.readinessWord {
                        PFLabeled(label: "Readiness", text: readinessText(word))
                    }
                }
            }
            .containerIdentifier("pf-nba-why")
        }
    }

    private func readinessText(_ word: String) -> String {
        var text = PFFormat.capitalized(word)
        if !next.readinessEvidence.isEmpty { text += ": " + next.readinessEvidence.joined(separator: "; ") }
        return text
    }

    private var optionsCard: some View {
        PFCard("Other options", icon: "list.number") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(next.runnerUps) { option in
                    VStack(alignment: .leading, spacing: 6) {
                        PFInsightActionRow(action: option.action)
                        if let reason = option.reason {
                            Text(reason)
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                    }
                    if option.id != next.runnerUps.last?.id { Divider().overlay(StrandPalette.hairline) }
                }
            }
        }
        .containerIdentifier("pf-nba-options")
    }

    private var rankingCard: some View {
        PFCard("How it is ranked", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 8) {
                if let considered = next.considered, let topics = next.topics {
                    PFParagraph("\(considered) candidate actions across \(topics) topics; one action per topic.")
                }
                if let basis = next.rankingBasis { PFParagraph(basis) }
            }
        }
    }
}
