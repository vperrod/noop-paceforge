#if os(iOS)
import SwiftUI
import StrandDesign
import StrandAnalytics

// MARK: - Look: Today pieces
//
// The iPhone Today pieces that sit on the look components: the Health and Stress monitor tiles and the My Day
// section (header + today's activities). Each reads the same data the rest of Today reads; nothing here scores
// or stores anything.

// MARK: Health monitor

/// Health monitor tile. With PaceForge's daily-intel.json it reads each vital against its own 30-day range:
/// "WITHIN RANGE · 4/4 metrics", or the worst vital ("VERY ELEVATED · Respiratory rate") in red, and opens the Health
/// monitor screen. Without it (PaceForge not set up or not reachable) it keeps to what the illness early-warning
/// already knows: red when it has raised an alert, calm otherwise, opening the Health screen.
/// Its own leaf, because it observes AppModel (see HealthAlertBanner for why that is kept out of Today's body).
struct LookHealthTile: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var intelStore = PFDailyIntelStore.shared

    /// Today's tile text from the server, when the file is today's and the Health monitor has vitals.
    private var monitorTile: PFHealthTile? { intelStore.current?.health?.tile }

    var body: some View {
        NavigationLink(value: monitorTile == nil ? TabRoute.health : TabRoute.healthMonitor) { tile }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-health-tile")
            .task { await intelStore.refreshIfStale() }
    }

    @ViewBuilder private var tile: some View {
        if let monitor = monitorTile {
            PFHealthMonitorTile(tile: monitor)
        } else if let alert = model.healthAlert {
            MonitorTile(title: String(localized: "Health monitor"), badge: .symbol("exclamationmark"),
                        badgeForeground: Color(hex: "#E8505A"), badgeBackground: NoopLook.alertWash,
                        status: String(localized: "ELEVATED"), statusColor: NoopLook.alert,
                        detail: alert.firedSignals.first ?? String(localized: "Body looks strained"))
        } else {
            MonitorTile(title: String(localized: "Health monitor"), badge: .symbol("checkmark"),
                        badgeForeground: NoopLook.trendUp, badgeBackground: NoopLook.trendUp.opacity(0.16),
                        status: String(localized: "NO ALERTS"), statusColor: NoopLook.trendUp,
                        detail: String(localized: "Signals look typical"))
        }
    }
}

// MARK: Stress monitor

struct LookStressTile: View {
    /// Stress score 0-3, or nil while the baseline is still building.
    let score: Double?

    var body: some View {
        NavigationLink(value: TabRoute.stress) { tile }
            .buttonStyle(.plain)
            .accessibilityIdentifier("look-stress-tile")
    }

    @ViewBuilder private var tile: some View {
        if let value = score {
            let level = LookStressLevel.forScore(value)
            let color = NoopLook.color(for: level)
            MonitorTile(title: String(localized: "Stress monitor"),
                        badge: .text(String(format: "%.1f", locale: AppLanguage.activeLocale, value)),
                        badgeForeground: color, badgeBackground: color.opacity(0.2),
                        status: level.label, statusColor: color, detail: String(localized: "Scale 0 to 3"))
        } else {
            MonitorTile(title: String(localized: "Stress monitor"), badge: .symbol("hourglass"),
                        badgeForeground: NoopLook.textTertiary, badgeBackground: NoopLook.track,
                        status: String(localized: "CALIBRATING"), statusColor: NoopLook.textTertiary,
                        detail: String(localized: "Needs more worn nights"))
        }
    }
}

// MARK: My Day

/// Maps a day timeline onto activity rows. Only things that happened: sleep, naps and workouts.
enum LookActivityMapper {
    static let maxRows = 5

    static func items(from events: [DayTimeline.Event]) -> [ActivityPillItem] {
        let clock = AppClock.hourMinuteFormatter()
        let wanted = events.filter { $0.kind == .sleep || $0.kind == .nap || $0.kind == .workout }
            .sorted { $0.start < $1.start }
        return wanted.prefix(maxRows).map { (event: DayTimeline.Event) -> ActivityPillItem in
            let minutes = (event.metrics.durationSec ?? Int((event.end ?? event.start).timeIntervalSince(event.start))) / 60
            let color = pillColor(event.kind)
            return ActivityPillItem(
                id: event.id, pillColor: color, icon: MyDayStyle.symbol(event),
                pillText: LookFormat.hoursMinutes(minutes: minutes), title: event.title,
                startText: clock.string(from: event.start), endText: event.end.map { clock.string(from: $0) },
                barColor: color)
        }
    }

    static func pillColor(_ kind: DayTimeline.Kind) -> Color {
        switch kind {
        case .sleep: return NoopLook.rest
        case .nap: return NoopLook.stageLight
        default: return NoopLook.effort
        }
    }
}

/// "My Day" header (opens My Day), today's activities and the Add / Start buttons.
struct LookMyDaySection: View {
    let day: Date
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var router: NavRouter
    @State private var items: [ActivityPillItem] = []
    @State private var showLiveWorkout = false
    @State private var showStartSport = false

    private var loadKey: String { "\(repo.refreshSeq)|\(Int(day.timeIntervalSince1970))" }

    var body: some View {
        VStack(spacing: 12) {
            header
            ActivitiesCard(items: items, onAdd: { router.requestQuickActions() }, onStart: startTapped)
                .accessibilityIdentifier("look-activities-card")
        }
        .task(id: loadKey) { await load() }
        // The in-exercise view and the sport picker, exactly as WorkoutStartControl presents them.
        .sheet(isPresented: $showLiveWorkout) {
            LiveWorkoutView(onClose: { showLiveWorkout = false })
                .environmentObject(model.live)
        }
        .workoutSelectionCover(isPresented: $showStartSport) {
            StartWorkoutSheet { name in
                model.startWorkout(sport: name)
                showLiveWorkout = true
            }
        }
    }

    private var header: some View {
        HStack {
            NavigationLink(value: TabRoute.myDay) {
                HStack(spacing: 6) {
                    Text(String(localized: "My Day"))
                        .font(LookFont.text(22, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("My Day")
            .accessibilityHint("Opens the timeline of the day")
            .accessibilityIdentifier("myday-entry")
            Spacer(minLength: 8)
            Button { router.requestQuickActions() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Quick actions")
        }
    }

    private func startTapped() {
        if model.activeWorkout == nil { showStartSport = true } else { showLiveWorkout = true }
    }

    @MainActor private func load() async {
        let result = await DayTimelineLoader.load(
            repo: repo, day: day,
            options: DayTimelineLoader.Options(includeHeartRate: false, includeStress: false, includeContext: false))
        guard !Task.isCancelled else { return }
        items = LookActivityMapper.items(from: result.timeline.events)
    }
}
#endif
