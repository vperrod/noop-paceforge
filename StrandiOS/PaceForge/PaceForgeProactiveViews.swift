import SwiftUI
import StrandDesign

// The coach's proactive messages (PaceForgeProactive.swift): the "Coach noticed" card on Today and the full list at the top of the
// Coach's Insights chip.

/// One message: tone mark, title, text, source, and the way to ask the coach about it. With `asksOnTap` the whole row asks (the
/// Insights list, where the group's colour stands in for the tone mark) instead of a button under it.
private struct PFProactiveRow: View {
    let message: PFProactiveMessage
    var showsDate = false
    var asksOnTap = false
    @EnvironmentObject private var router: NavRouter
    private let hiding = PFHiding()

    private var toneColor: Color {
        switch message.tone {
        case .good: return NoopLook.trendUp
        case .watch: return NoopLook.trendDown
        case .info: return NoopLook.sufficient
        }
    }

    private var toneIcon: String {
        switch message.tone {
        case .good: return "checkmark.circle.fill"
        case .watch: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func ask() {
        // With Hide numbers on, the coach gets the hidden text, never the figures.
        PFChatPrefill.shared.text = hiding.text(message.text)
        UserDefaults.standard.set("ask", forKey: CoachChip.storageKey)
        router.openCoach()
    }

    var body: some View {
        if asksOnTap {
            Button(action: ask) { content }
                .buttonStyle(.plain)
                .accessibilityHint("Asks the coach about this")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: 10) {
            if !asksOnTap {
                Image(systemName: toneIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(toneColor)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if showsDate {
                    Text(hiding.text(PFFormat.dayTitle(message.date))).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                }
                if let title = message.title {
                    Text(hiding.text(title)).font(LookFont.text(15, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(hiding.text(message.text)).font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    PFSourceTag(source: message.source)
                    if !asksOnTap {
                        Button("Ask the coach about this", action: ask)
                            .font(LookFont.text(12, weight: .semibold))
                            .foregroundStyle(NoopLook.textSecondary)
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

/// Today: what the coach noticed today or yesterday (at most two). Draws nothing when there is none.
struct PFProactiveTodayCard: View {
    @ObservedObject private var store = PFProactiveStore.shared
    @EnvironmentObject private var router: NavRouter

    var body: some View {
        let shown = store.doc?.forToday(PFAPI.todayISO) ?? []
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coach noticed").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
                ForEach(shown) { PFProactiveRow(message: $0) }
                Button {
                    UserDefaults.standard.set(CoachChip.insights.rawValue, forKey: CoachChip.storageKey)
                    router.openCoach()
                } label: {
                    HStack {
                        Text("All insights").font(LookFont.text(13, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(NoopLook.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-proactive-all")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .accessibilityIdentifier("today-proactive")
        }
    }
}

/// Coach > Insights: the last 14 days of messages, one card per heading with its colour down the left edge. A tap on a message asks the coach.
struct PFProactiveInsightsSection: View {
    @ObservedObject private var store = PFProactiveStore.shared

    private func stripe(_ group: PFProactiveGroup) -> Color {
        switch group {
        case .working: return NoopLook.trendUp
        case .costing: return NoopLook.trendDown
        case .trends: return PFColor.violet
        case .races: return PFColor.sky
        }
    }

    var body: some View {
        let groups = store.doc?.groups(PFAPI.todayISO) ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("What the coach noticed").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
            if groups.isEmpty {
                Text("Nothing new from the coach in the last two weeks.")
                    .font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.group.title).font(LookFont.text(14, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
                    ForEach(entry.messages) { PFProactiveRow(message: $0, showsDate: true, asksOnTap: true) }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Capsule().fill(stripe(entry.group)).frame(width: 3) }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            }
        }
        .accessibilityIdentifier("coach-proactive")
        .task { await store.refreshIfStale() }
    }
}
