import SwiftUI
import StrandDesign

// The coach's proactive messages (PaceForgeProactive.swift): the "Coach noticed" card on Today and the full list at the top of the
// Coach's Insights chip.

/// One message: tone mark, title, text, source, and the way to ask the coach about it.
private struct PFProactiveRow: View {
    let message: PFProactiveMessage
    var showsDate = false
    @EnvironmentObject private var router: NavRouter

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

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toneIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(toneColor)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if showsDate {
                    Text(PFFormat.dayTitle(message.date)).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                }
                if let title = message.title {
                    Text(title).font(LookFont.text(15, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(message.text).font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    PFSourceTag(source: message.source)
                    Button("Ask the coach about this") {
                        PFChatPrefill.shared.text = message.text
                        UserDefaults.standard.set("ask", forKey: CoachChip.storageKey)
                        router.openCoach()
                    }
                    .font(LookFont.text(12, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Coach > Insights: the last 14 days of messages under their headings.
struct PFProactiveInsightsSection: View {
    @ObservedObject private var store = PFProactiveStore.shared

    var body: some View {
        let groups = store.doc?.groups(PFAPI.todayISO) ?? []
        VStack(alignment: .leading, spacing: 14) {
            Text("What the coach noticed").lookCaps(12.5).foregroundStyle(NoopLook.textPrimary)
            if groups.isEmpty {
                Text("Nothing new from the coach in the last two weeks.")
                    .font(LookFont.text(13, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
            }
            ForEach(Array(groups.enumerated()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 12) {
                    Text(entry.group.title).font(LookFont.text(13, weight: .semibold)).foregroundStyle(NoopLook.textSecondary)
                    ForEach(entry.messages) { PFProactiveRow(message: $0, showsDate: true) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityIdentifier("coach-proactive")
        .task { await store.refreshIfStale() }
    }
}
