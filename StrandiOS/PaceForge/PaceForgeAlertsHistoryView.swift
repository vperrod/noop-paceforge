import SwiftUI
import StrandDesign

/// The Alerts screen behind the bell on NOOP Today: unread lines first with a dot, then the history as Today, Yesterday and Earlier.
/// A line is a PaceForge alert the server still keeps or a Needs you item this phone announced. Tapping one marks it read and opens
/// what a tap on its notification opens: it hands that notification's payload to `onOpen` and closes, and the bell opens it once the
/// sheet is gone (`PFAlertLink`). The Telegram messages are not here: the app cannot see them.
struct PFAlertsHistoryView: View {
    let onOpen: ([AnyHashable: Any]) -> Void

    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var history = PFAlertHistoryStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = history.entries(for: model.snapshot)
        let seen: Set<String> = history.seen.map { Set($0) } ?? Set(entries.map { $0.id })
        let sections = PFAlertHistory.sections(entries, seen: seen, now: Date(), calendar: Calendar.current)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if sections.isEmpty {
                        Text("No alerts yet. PaceForge alerts and the questions it asks you show here.")
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("pf-alerts-empty")
                    }
                    ForEach(sections, id: \.group.rawValue) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(Self.title(section.group))
                                .lookCaps(12.5)
                                .foregroundStyle(NoopLook.textTertiary)
                            ForEach(section.entries) { entry in
                                row(entry, isUnread: section.group == .unread)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Mark all read") { history.markAllRead(entries) }
                        .foregroundStyle(StrandPalette.accent)
                        .disabled(PFAlertHistory.unreadCount(entries, seen: seen) == 0)
                        .accessibilityIdentifier("pf-alerts-mark-all")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .onAppear { history.adopt(model.snapshot) }
    }

    private func row(_ entry: PFAlertEntry, isUnread: Bool) -> some View {
        Button { open(entry) } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isUnread ? StrandPalette.accent : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title)
                        .font(StrandFont.subhead.weight(isUnread ? .bold : .semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = entry.body {
                        Text(body)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        PFChip(text: Self.tagLabel(entry.tag), color: Self.tagColor(entry))
                        if let status = entry.status {
                            PFChip(text: Self.statusLabel(status), color: Self.statusColor(status))
                        }
                        Spacer(minLength: 0)
                        Text(Self.relative(entry.date))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread") : Text(verbatim: ""))
        .accessibilityIdentifier("pf-alert-row-\(entry.id)")
    }

    /// Marks the line read, hands over what a tap on its notification opens and closes the screen.
    private func open(_ entry: PFAlertEntry) {
        history.markRead([entry.id])
        onOpen(entry.userInfo)
        dismiss()
    }

    private static func title(_ group: PFAlertGroup) -> LocalizedStringKey {
        switch group {
        case .unread: return "Unread"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .earlier: return "Earlier"
        }
    }

    private static func tagLabel(_ tag: PFAlertTag) -> String {
        switch tag {
        case .inputNeeded: return String(localized: "Input needed")
        case .loadSpike: return String(localized: "Load spike")
        case .loadRamp: return String(localized: "Load ramp")
        case .sleepDebt: return String(localized: "Sleep debt")
        case .hrvLow: return String(localized: "HRV low")
        case .restingHeartRate: return String(localized: "Resting heart rate up")
        case .lowReadiness: return String(localized: "Low readiness")
        case .poorRecharge: return String(localized: "Poor recharge")
        case .weighIn: return String(localized: "Weigh-in")
        case .hydration: return String(localized: "Hydration")
        case .heartRateRecovery: return String(localized: "Heart-rate recovery")
        case .healthMonitor: return String(localized: "Health monitor")
        case .live: return String(localized: "Live alert")
        case .other: return String(localized: "Alert")
        }
    }

    private static func tagColor(_ entry: PFAlertEntry) -> Color {
        if entry.source == .needsYou { return StrandPalette.accent }
        switch entry.severity {
        case "act": return PFColor.critical
        case "watch": return PFColor.warning
        default: return PFColor.sky
        }
    }

    private static func statusLabel(_ status: PFAlertStatus) -> String {
        switch status {
        case .open: return String(localized: "Still open")
        case .dismissed: return String(localized: "Dismissed")
        case .done: return String(localized: "Done")
        case .answered: return String(localized: "Answered")
        }
    }

    private static func statusColor(_ status: PFAlertStatus) -> Color {
        switch status {
        case .open: return PFColor.warning
        case .dismissed: return StrandPalette.textTertiary
        case .done, .answered: return PFColor.positive
        }
    }

    private static func relative(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLanguage.activeLocale
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
