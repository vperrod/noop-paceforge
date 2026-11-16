import SwiftUI
import StrandDesign

// MARK: - Journal widget (Today screen) — #627
//
// A persistent Today widget for the Journal: a WHOOP-style strip of the last `stripDays` days
// (filled = a journal entry that day, today ringed) plus an always-present tap-through to the journal.
// The Journal (behavioural logging that feeds Insights / "What Moves You") is otherwise only reachable
// inside the Insights screen, which isn't a primary destination — easy to forget, and the only proactive
// prompt is the once-a-morning sleep sheet — missed on any day you don't open Sleep. This surfaces it on
// Today where it can't be missed, and doubles as the "direct link to Insights" the report (#627) asked for.
//
// Build 529: the card asks about YESTERDAY. You answer in the morning about last night, and the server pairs each day's answers with the
// next morning's recovery, so a day's answers belong to that day. It opens the journal on yesterday, and folds once yesterday is logged.
//
// Opt-out via `PuffinExperiment.journalReminderKey` (default ON — the same key also gates the Android
// morning sleep sheet twin). Read-only: it never writes a journal entry. Twin of Android
// `JournalReminderCard` (android/.../ui/JournalReminder.kt). Design-Reset compliant — a flat accent-tinted
// NoopCard, NoopMetrics / StrandPalette / StrandFont tokens, matching the other Today cards.

struct JournalReminderCard: View {

    @EnvironmentObject var repo: Repository
    @EnvironmentObject var router: NavRouter

    /// Default ON so the reminder works out of the box; the Settings toggle / this key opt out.
    @AppStorage(PuffinExperiment.journalReminderKey) private var reminderEnabled = true

    /// Which of the last `stripDays` day-keys carry a native journal entry. nil = still loading / read
    /// error → render nothing (never a misleading all-empty strip).
    @State private var loggedDays: Set<String>?
    /// The app's logical day (rolls at 04:00) the strip was drawn for: when it changes the strip is drawn again, so a tap and what was
    /// drawn always agree on which day a bar is.
    @State private var logicalDayKey = Repository.logicalDayKey(Date())

    private static let stripDays = 7

    var body: some View {
        // The loader is its own always-present, zero-size view: a `.task` on content that is empty until the data has loaded can wait
        // for ever for the data it is meant to load (the card did not show in the UI-test runs).
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: JournalReminderLoadKey(seq: repo.refreshSeq, enabled: reminderEnabled)) { await reload() }
            content
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            let key = Repository.logicalDayKey(Date())
            if key != logicalDayKey { logicalDayKey = key }
        }
    }

    @ViewBuilder private var content: some View {
        Group {
            if reminderEnabled, let logged = loggedDays {
                #if os(iOS)
                // Once yesterday's journal is in, the card folds to one row that opens what helps and hurts recovery.
                if logged.contains(Self.yesterdayKey()) {
                    loggedRow
                } else {
                    card(logged)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("today-journal")
                }
                #else
                card(logged)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("today-journal")
                #endif
            }
        }
    }

    #if os(iOS)
    private var loggedRow: some View {
        NavigationLink(value: TabRoute.journalImpact) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityHidden(true)
                Text(String(localized: "Journal logged \u{00B7} see what helps and hurts"))
                    .font(LookFont.text(14, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-journal-logged")
    }
    #endif

    private func card(_ logged: Set<String>) -> some View {
        // The keys and the shift of one instant, held together: a bar tapped later still opens the day it was drawn as.
        let now = Date()
        let shift = Self.calendarShift(now)
        let keys = Self.dayKeys(now)
        _ = logicalDayKey
        let todayKey = keys.last ?? ""
        let yesterdayKey = keys.dropLast().last ?? ""
        let yesterdayLogged = logged.contains(yesterdayKey)
        // A recent PAST day with no entry — surfaces the tap-a-bar-to-backfill interaction once yesterday is
        // done (#656). Accent while anything is actionable; calm secondary once fully caught up. Today is not due yet.
        let hasMissed = keys.contains { $0 != todayKey && !logged.contains($0) }
        let subtitle: String = !yesterdayLogged ? String(localized: "What happened yesterday?")
            : hasMissed ? String(localized: "Tap a day to catch up")
            : String(localized: "Logged yesterday")
        // No outer Button: each bar is its own tap target that deep-links the journal to THAT day (#656),
        // and nested SwiftUI buttons don't work — so header + subtitle carry their own onTapGesture (→
        // today) and the bars carry theirs. The regions are non-overlapping in the VStack, so a tap lands
        // on exactly one. Tapping a bar does NOT set today, so a bar's day always wins.
        return surface {
            VStack(alignment: .leading, spacing: NoopMetrics.space3) {
                HStack(spacing: NoopMetrics.space2) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 18))
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityHidden(true)
                    #if os(iOS)
                    Text(String(localized: "Journal")).lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                    #else
                    Text(String(localized: "Journal"))
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    #endif
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
                .onTapGesture { router.openJournal(day: 1 + shift) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(Text(String(localized: "Journal")))
                .accessibilityHint(Text(String(localized: "Open journal")))
                // The last-N-days strip: one equal-width bar per day, each its own tap target. Filled =
                // logged; today is ringed. Tapping a bar deep-links the journal to that day (#656).
                HStack(spacing: 6) {
                    ForEach(keys.indices, id: \.self) { i in
                        let key = keys[i]
                        let off = Self.stripDays - 1 - i          // keys[0] = 6 days ago … last = today
                        let isLogged = logged.contains(key)
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)                    // taller invisible tap target
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(isLogged ? StrandPalette.accent : StrandPalette.textTertiary.opacity(0.22))
                                    .frame(height: 10)
                                    .overlay {
                                        if off == 1, !isLogged {
                                            RoundedRectangle(cornerRadius: 3)
                                                .strokeBorder(StrandPalette.accent, lineWidth: 1)
                                        }
                                    }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { router.openJournal(day: off + shift) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(Self.barLabel(off))
                    }
                }
                Text(subtitle)
                    .font(StrandFont.footnote)
                    .foregroundStyle((!yesterdayLogged || hasMissed) ? StrandPalette.accent : StrandPalette.textSecondary)
                    .contentShape(Rectangle())
                    .onTapGesture { router.openJournal(day: 1 + shift) }
                    .accessibilityAddTraits(.isButton)   // it opens the journal — announce it as one
            }
        }
    }

    /// WHOOP's card on the iPhone: a 12 pt tile on the dark gradient. The Mac keeps the accent-tinted frosted card.
    @ViewBuilder private func surface<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        #if os(iOS)
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        #else
        NoopCard(tint: StrandPalette.accent) { content() }
        #endif
    }

    /// Screen-reader label for a strip bar (#656): the day it deep-links to. Twin of JournalLogCard's
    /// day-picker labels; "%lld days ago" is a String Catalog key so it stays localized.
    private static func barLabel(_ offset: Int) -> LocalizedStringKey {
        switch offset {
        case 0: return "Today"
        case 1: return "Yesterday"
        default: return "\(offset) days ago"
        }
    }

    private func reload() async {
        guard reminderEnabled else { loggedDays = nil; return }
        let keys = Self.dayKeys()
        var days = await repo.nativeJournalDays(from: keys.first ?? "", to: keys.last ?? "")
        #if DEBUG
        // UI tests: the demo data logs every day up to yesterday, so `-JournalYesterdayUnlogged` takes yesterday out to show the prompt.
        if ProcessInfo.processInfo.arguments.contains("-JournalYesterdayUnlogged") { days.remove(Self.yesterdayKey()) }
        #endif
        loggedDays = days
    }

    /// Yesterday's local-day key: the one before the last of `dayKeys()`.
    private static func yesterdayKey() -> String {
        dayKeys().dropLast().last ?? ""
    }

    /// How many calendar days the app's logical today (it rolls at 04:00) is behind the calendar's: 1 between midnight and 04:00, else 0.
    /// The journal screen counts its day offsets from the calendar day, so an offset taken from the strip here is moved by this.
    private static func calendarShift(_ now: Date = Date()) -> Int {
        Repository.localDayKey(now) == Repository.logicalDayKey(now) ? 0 : 1
    }

    /// The `stripDays` local-day keys (yyyy-MM-dd), oldest → the app's logical today (04:00 roll), matching Android's `journalDayKey`
    /// (civil-day arithmetic via Calendar so a DST edge can't mislabel a day).
    private static func dayKeys(_ now: Date = Date()) -> [String] {
        let cal = Calendar.current
        let today = Repository.logicalDay(now)
        return (0..<stripDays).reversed().map { n in
            Repository.localDayKey(cal.date(byAdding: .day, value: -n, to: today) ?? today)
        }
    }
}

/// Reload key: a sync (seq) or toggle flip re-reads completion. Mirrors `AutoWorkoutLoadKey`.
private struct JournalReminderLoadKey: Equatable {
    let seq: Int
    let enabled: Bool
}
