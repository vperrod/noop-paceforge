import SwiftUI
import StrandDesign

/// A2: the inbox behind the bell on Today. Everything the athlete was told, newest first, new ones marked: the items of `data/inbox.json`
/// and the earlier alert history the bell showed before (an alert the server still keeps, a Needs you item the phone announced). Chips
/// filter it, a tap opens what the line is about (`PFInboxRouter529`), and one row leads to the switch per kind.
struct PFInbox529: View {
    /// The bell's sheet passes this: it closes the sheet and opens the row once the sheet is gone. Nil when the inbox is pushed over the
    /// Plan tab or opened by a link: the row opens at once.
    var onOpen: ((PFInboxRow529) -> Void)?

    @ObservedObject private var store = PFInboxStore529.shared
    @ObservedObject private var history = PFAlertHistoryStore.shared
    @ObservedObject private var model = PFUnified.model
    @State private var filter: PFInboxFilter529 = .all
    private let hiding = PFHiding()

    init(onOpen: ((PFInboxRow529) -> Void)? = nil) {
        self.onOpen = onOpen
    }

    var body: some View {
        let rows = store.rows()
        let unread = Set(store.unreadRows().map(\.id))
        let shown = PFInboxLogic529.filtered(rows, by: filter)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header(unreadCount: unread.count)
                SectionChips(options: PFInboxFilter529.allCases, selection: $filter, idPrefix: "plan529-inbox-chip",
                             id: { $0.rawValue }, title: { $0.title })
                if store.isStale {
                    Text("Showing the copy saved on this phone. PaceForge could not be reached.")
                        .font(PFPlanFont543.text(12.5, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityIdentifier("plan529-inbox-stale")
                }
                list(rows: rows, shown: shown, unread: unread)
                NavigationLink { PFInboxSettings529() } label: { settingsRow }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan529-inbox-settings")
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("Inbox")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("plan529-inbox")
        .task {
            await store.refresh()
            history.adopt(model.snapshot)
        }
    }

    // MARK: Parts

    private func header(unreadCount: Int) -> some View {
        HStack {
            Text(unreadCount > 0 ? "\(unreadCount) new" : "Nothing new")
                .pfCaps(12.5)
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityIdentifier("plan529-inbox-new")
            Spacer(minLength: 8)
            Button("Mark all read") { store.markAllRead() }
                .font(PFPlanFont543.text(13, weight: .medium))
                .foregroundStyle(StrandPalette.accent)
                .disabled(unreadCount == 0)
                .accessibilityIdentifier("plan529-inbox-mark-all")
        }
    }

    @ViewBuilder private func list(rows: [PFInboxRow529], shown: [PFInboxRow529], unread: Set<String>) -> some View {
        if rows.isEmpty {
            switch store.load {
            case .loading:
                note("Loading", id: "plan529-inbox-loading")
            case .failed:
                VStack(alignment: .leading, spacing: 10) {
                    Text("PaceForge could not be reached.")
                        .font(PFPlanFont543.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Button("Try again") { Task { await store.refresh() } }
                        .font(PFPlanFont543.text(14, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("plan529-inbox-retry")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .containerIdentifier("plan529-inbox-failed")
            case .loaded:
                note("Nothing yet. What the coach tells you, your reports and your alerts show here.", id: "plan529-inbox-empty")
            }
        } else if shown.isEmpty {
            note("Nothing under \(filter.title).", id: "plan529-inbox-filter-empty")
        } else {
            VStack(spacing: 8) {
                ForEach(shown) { row in
                    rowView(row, isUnread: unread.contains(row.id))
                }
            }
            .containerIdentifier("plan529-inbox-list")
        }
    }

    private func note(_ text: String, id: String) -> some View {
        Text(text)
            .font(PFPlanFont543.text(14, weight: .medium))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .accessibilityIdentifier(id)
    }

    private func rowView(_ row: PFInboxRow529, isUnread: Bool) -> some View {
        Button { open(row) } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(isUnread ? StrandPalette.accent : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                Text(Self.timeText(row.date))
                    .font(PFPlanFont543.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .frame(width: 56, alignment: .leading)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hiding.text(row.title))
                        .font(PFPlanFont543.text(15, weight: isUnread ? .bold : .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = row.subtitle {
                        Text(hiding.text(subtitle))
                            .font(PFPlanFont543.text(13, weight: .medium))
                            .foregroundStyle(NoopLook.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isUnread ? Text("Unread") : Text(verbatim: ""))
        .accessibilityIdentifier("plan529-inbox-row-\(row.id)")
    }

    private var settingsRow: some View {
        HStack {
            Text("Choose what you are told about")
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .contentShape(Rectangle())
    }

    // MARK: Actions

    private func open(_ row: PFInboxRow529) {
        store.markRead(row)
        if let onOpen { onOpen(row) } else { PFInboxRouter529.open(row) }
    }

    // MARK: Time

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayMonth: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("dMMM")
        return f
    }()

    /// "19:32" today, "Yesterday", else "14 Nov". Today is the app's day (`PFAPI.todayISO`, the phone's day unless a UI-test fixture fixes one).
    private static func timeText(_ date: Date?) -> String {
        guard let date else { return "" }
        let day = PFFormat.isoString(date)
        let today = PFAPI.todayISO
        if day == today { return clock.string(from: date) }
        if day == PFFormat.addDays(today, -1) { return "Yesterday" }
        return dayMonth.string(from: date)
    }
}

/// "Choose what you are told about": one switch per kind, kept on the phone, and under them when the phone last asked the server and
/// how late the newest notification was (the real delay, for measuring after the build).
struct PFInboxSettings529: View {
    @ObservedObject private var store = PFInboxStore529.shared
    @State private var badgesOff = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if badgesOff { badgesRow }
                VStack(spacing: 0) {
                    ForEach(PFInboxKind529.allCases) { kind in
                        Toggle(isOn: Binding(get: { store.isOn(kind) }, set: { store.set(kind, on: $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.switchTitle)
                                    .font(PFPlanFont543.text(15, weight: .semibold))
                                    .foregroundStyle(NoopLook.textPrimary)
                                Text(kind.switchDetail)
                                    .font(PFPlanFont543.text(12.5, weight: .medium))
                                    .foregroundStyle(NoopLook.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(StrandPalette.accent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("plan529-inbox-switch-\(kind.rawValue)")
                        if kind != PFInboxKind529.allCases.last {
                            Rectangle().fill(NoopLook.divider).frame(height: 1)
                        }
                    }
                }
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                Text("A switch off stops the notification only. The line still shows in the inbox. Health alerts also follow the alerts switch in the PaceForge sync settings.")
                    .font(PFPlanFont543.text(12.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                diagnostics
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle("What you are told about")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("plan529-inbox-settings-screen")
        .task { badgesOff = await PFBadgePermission529.badgesAreOff() }
    }

    /// Notifications are allowed but the app icon cannot show the unread count: iOS badges are off for NOOP.
    private var badgesRow: some View {
        HStack(spacing: 12) {
            Text("Badges are off in iOS Settings")
                .font(PFPlanFont543.text(14, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 4)
            Button("Open settings") { PFBadgePermission529.openNotificationSettings() }
                .font(PFPlanFont543.text(14, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .accessibilityIdentifier("plan529-inbox-badges-open")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .containerIdentifier("plan529-inbox-badges-off")
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last check")
                .pfCaps(11.5)
                .foregroundStyle(NoopLook.textSecondary)
            Text(lastCheckText)
                .font(PFPlanFont543.text(14, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("plan529-inbox-last-check")
            Text(lastDelayText)
                .font(PFPlanFont543.text(13, weight: .medium))
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityIdentifier("plan529-inbox-last-delay")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan529-inbox-diagnostics")
    }

    private var lastCheckText: String {
        guard let date = store.lastCheck else { return "Not yet. The phone asks while the strap keeps NOOP awake, at most every 10 minutes." }
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEEdMMMHHmm")
        return f.string(from: date)
    }

    private var lastDelayText: String {
        guard let delay = store.lastNewDelay else { return "No new item has come in since this was switched on." }
        return "The last new item reached the phone \(PFInboxLogic529.delayText(delay)) after PaceForge wrote it."
    }
}
