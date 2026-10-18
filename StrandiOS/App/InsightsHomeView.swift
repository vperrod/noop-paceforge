#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Insights: the one screen
//
// What used to be four screens named Insights, Intelligence, What Moves You and Journal impact is one: a row of sections at the top and
// the chosen section below. Nothing was dropped: each section is the content of the screen it replaces.
//
// - Training    PaceForge's fitness / fatigue / form, load warnings, races and HYROX prognosis (only inside the PaceForge tab, which has
//               the snapshot it is drawn from)
// - Journal     the journal flow, mood, caffeine and the ranked behaviours (the old Insights)
// - What moves you   the ranked, lag-aware effects and the alcohol / caffeine dose-response
// - Intelligence     NOOP's own Charge / Effort / Rest by day
// - Reports     Highlights, Healthspan, the Monthly report and Journal impact, each opening its own screen
//
// NOOP's and PaceForge's scores are never merged: the Training section is PaceForge's, the other sections are NOOP's, and each says so.

enum InsightsSection: String, CaseIterable, Identifiable {
    case training, journal, moves, intelligence, reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .training: return "Training"
        case .journal: return "Journal"
        case .moves: return "What moves you"
        case .intelligence: return "Intelligence"
        case .reports: return "Reports"
        }
    }
}

/// The sections and the one on show. `snapshot` is nil outside the PaceForge tab, which hides Training.
struct InsightsSections: View {
    let snapshot: PFSnapshot?
    @Binding var selection: InsightsSection

    private var available: [InsightsSection] {
        snapshot == nil ? InsightsSection.allCases.filter { $0 != .training } : InsightsSection.allCases
    }

    private var shown: InsightsSection { available.contains(selection) ? selection : (available.first ?? .journal) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chips
            switch shown {
            case .training:
                if let snapshot { PFInsightsView(snapshot: snapshot) }
            case .journal:
                InsightsView(embedded: true)
            case .moves:
                InsightsHubView(embedded: true)
            case .intelligence:
                IntelligenceView(embedded: true)
            case .reports:
                InsightsReports()
            }
        }
        .containerIdentifier("insights-sections")
    }

    private var chips: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(available) { section in
                let isOn = section == shown
                Button { selection = section } label: {
                    Text(section.title)
                        .lookCaps(12)
                        .foregroundStyle(isOn ? NoopLook.textPrimary : NoopLook.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(isOn ? NoopLook.segmentOn : NoopLook.segmentOff))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("insights-section-\(section.rawValue)")
            }
        }
    }
}

/// The Reports section: Highlights, Healthspan, the Monthly report and Journal impact, each one tap to its own screen. Highlights is
/// the same screen the streak chip on Today opens.
struct InsightsReports: View {
    private struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let route: TabRoute
    }

    private static let entries = [
        Entry(id: "highlights", title: "Highlights", detail: "Records, streaks and notable stats", icon: "star.fill", route: .highlights),
        Entry(id: "healthspan", title: "Healthspan", detail: "Body age range and pace of aging", icon: "hourglass", route: .healthspan),
        Entry(id: "monthly", title: "Monthly report", detail: "Last month and the month so far", icon: "calendar", route: .monthlyReport),
        Entry(id: "impact", title: "Journal impact", detail: "What helps and hurts the next morning's score", icon: "book.closed.fill", route: .journalImpact),
    ]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(Self.entries) { entry in
                NavigationLink(value: entry.route) {
                    HStack(spacing: 14) {
                        Image(systemName: entry.icon)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(LookFont.text(16, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                            Text(entry.detail)
                                .font(LookFont.text(13, weight: .medium))
                                .foregroundStyle(NoopLook.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("insights-report-\(entry.id)")
            }
        }
        .containerIdentifier("insights-reports")
    }
}

/// The Insights screen in the More list and wherever else NOOP opens Insights (the journal quick action, the "what moves you" deep link).
struct InsightsHomeView: View {
    @State private var section: InsightsSection

    init(initial: InsightsSection = .journal) {
        _section = State(initialValue: initial)
    }

    var body: some View {
        ScreenScaffold(title: "Insights", subtitle: "Journal, what moves you, Intelligence and your reports.",
                       lazy: true, topBackground: liquidScaffoldSky()) {
            InsightsSections(snapshot: nil, selection: $section)
        }
    }
}

/// The PaceForge tab's Insights segment: the same sections as the Insights screen, with PaceForge's Training first.
struct PFInsightsHost: View {
    let snapshot: PFSnapshot
    @State private var section = InsightsSection.training

    var body: some View {
        InsightsSections(snapshot: snapshot, selection: $section)
    }
}
#endif
