import SwiftUI
import StrandAnalytics
import StrandDesign
import WhoopStore

// MARK: - My Day
//
// One calendar day, start to finish: a 24 h strip on top (heart rate, bands for sleep / naps / workouts /
// the plan, hatched grey where nothing was recorded, a marker at now) and every event of the day below it,
// newest first, each opening the screen that already exists for it. Scrubbing the strip highlights a time
// and scrolls the list to what was happening then.
//
// All composing rules (one workout from three sources, plan done or missed, gaps) live in the pure
// `DayTimeline` builder; this view only draws and routes.

/// Set once at launch by the iPhone app: the screen a PaceForge bike ride opens, from its ride id. Nil on a
/// platform with no ride screen, where the ride row simply does not open.
enum MyDayRideScreen {
    static var make: ((String) -> AnyView)?
}

struct MyDayView: View {
    @EnvironmentObject private var repo: Repository
    @EnvironmentObject private var intelligence: IntelligenceEngine
    @ObservedObject private var caffeineLog = CaffeineLogStore.shared

    @AppStorage("noop.myday.showStress") private var showStress = false
    @AppStorage("noop.myday.showSteps") private var showSteps = false
    @AppStorage("noop.myday.showEnergy") private var showEnergy = false
    @AppStorage("noop.myday.showGarminStress") private var showGarminStress = false
    @AppStorage(HydrationStore.enabledKey) private var hydrationEnabled = false
    @AppStorage(UnitPrefs.systemKey) private var unitSystemRaw = UnitSystem.metric.rawValue
    @AppStorage(UnitPrefs.distanceSystemKey) private var distanceSystemRaw = ""

    @State private var dayStart: Date
    @State private var loaded: DayTimelineLoader.Loaded?
    @State private var scrubDate: Date?
    @State private var highlightedId: String?
    @State private var sheet: Sheet?

    private enum Sheet: Identifiable {
        case addWorkout
        case addNap(bedTs: Int, wakeTs: Int)
        case workoutDetail(WorkoutRow)
        case sleep
        case ride(String)

        var id: String {
            switch self {
            case .addWorkout: return "addWorkout"
            case .addNap: return "addNap"
            case .workoutDetail(let row): return "detail-\(row.startTs)-\(row.endTs)-\(row.sport)-\(row.source)"
            case .sleep: return "sleep"
            case .ride(let id): return "ride-\(id)"
            }
        }
    }

    init(day: Date? = nil) {
        _dayStart = State(initialValue: Self.initialDayStart(day))
    }

    private var unitSystem: UnitSystem { UnitSystem(rawValue: unitSystemRaw) ?? .metric }
    private var distanceSystem: UnitSystem { UnitPrefs.resolveDistance(system: unitSystem, override: distanceSystemRaw) }
    private var timeline: DayTimeline? { loaded?.timeline }
    /// The logical day (it rolls over at the user's rollover hour, not midnight), the same one the stepper
    /// and the loader treat as the latest.
    private var isToday: Bool { dayStart == Repository.logicalDayStart(Date()) }

    private static func initialDayStart(_ day: Date?) -> Date {
        #if DEBUG
        if let fixtureDay = MyDayFixture.dayStart { return fixtureDay }
        #endif
        return day ?? Repository.logicalDayStart(Date())
    }

    var body: some View {
        ScreenScaffold(title: "My Day", subtitle: "Everything your day recorded, in order.",
                       onRefresh: { await repo.refresh(); await reload() },
                       trailing: { addMenu }) {
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
                    dayNav
                    if let timeline {
                        stripCard(timeline)
                        if !timeline.hasRecordedData { emptyState(timeline) }
                        eventList(timeline)
                    } else {
                        loadingCard
                    }
                }
                .onChangeCompat(of: scrubDate) { newValue in
                    guard let current = timeline, let newValue,
                          let target = Self.event(at: newValue, in: current) else { return }
                    guard target.id != highlightedId else { return }
                    highlightedId = target.id
                    withAnimation(StrandMotion.interactive) { proxy.scrollTo(target.id, anchor: .center) }
                }
            }
        }
        .task(id: loadKey) { await reload() }
        .sheet(item: $sheet) { sheet in sheetContent(sheet) }
    }

    // MARK: Loading

    private var loadKey: String {
        "\(Int(dayStart.timeIntervalSince1970))|\(repo.refreshSeq)|\(repo.hydrationSeq)|\(caffeineLog.intakes.count)|\(showStress)"
    }

    private func reload() async {
        #if DEBUG
        if let fixture = MyDayFixture.loaded() {
            loaded = fixture
            return
        }
        #endif
        let result = await DayTimelineLoader.load(repo: repo, day: dayStart,
                                                  options: DayTimelineLoader.Options(includeStress: showStress))
        guard !Task.isCancelled else { return }
        loaded = result
        // The widget reads the same day, so a fresh load of today refreshes its file.
        if isToday { MyDayWidgetBridge.publish(result.timeline) }
    }

    // MARK: Day stepper (FullDayChartView's conventions: flat accent chevrons, no future days)

    private var dayNav: some View {
        HStack(spacing: NoopMetrics.cardInnerSpacing) {
            Button { stepDay(-1) } label: {
                Image(systemName: "chevron.left").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(StrandPalette.accent)
            .accessibilityLabel("Previous day")
            .accessibilityIdentifier("myday-prev")

            Spacer()
            Text(dayLabel)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .monospacedDigit()
                .accessibilityIdentifier("myday-day")
            Spacer()

            Button { stepDay(1) } label: {
                Image(systemName: "chevron.right").font(StrandFont.headline.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(isOnLatestDay ? StrandPalette.textTertiary : StrandPalette.accent)
            .disabled(isOnLatestDay)
            .accessibilityLabel("Next day")
            .accessibilityIdentifier("myday-next")
        }
        .padding(.horizontal, NoopMetrics.space1)
    }

    private var isOnLatestDay: Bool { dayStart >= Repository.logicalDayStart(Date()) }

    private func stepDay(_ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: dayStart) else { return }
        if delta > 0 && next > Repository.logicalDayStart(Date()) { return }
        withAnimation(StrandMotion.interactive) {
            dayStart = next
            loaded = nil
            scrubDate = nil
            highlightedId = nil
        }
    }

    private var dayLabel: String {
        let calendar = Calendar.current
        let today = Repository.logicalDayStart(Date())
        if calendar.isDate(dayStart, inSameDayAs: today) { return String(localized: "Today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
           calendar.isDate(dayStart, inSameDayAs: yesterday) { return String(localized: "Yesterday") }
        return Self.dayFormatter.string(from: dayStart)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    // MARK: Strip card

    private func stripCard(_ timeline: DayTimeline) -> some View {
        NoopCard(tint: StrandPalette.metricRose) {
            VStack(alignment: .leading, spacing: NoopMetrics.cardInnerSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The day").strandOverline()
                    Spacer()
                    Text(readout(timeline))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("myday-readout")
                    if scrubDate != nil {
                        Button("Clear") { scrubDate = nil; highlightedId = nil }
                            .font(StrandFont.footnote)
                            .foregroundStyle(StrandPalette.accent)
                            .buttonStyle(.plain)
                    }
                }
                MyDayStrip(timeline: timeline, showStress: showStress, showSteps: showSteps, showEnergy: showEnergy,
                           showGarminStress: showGarminStress, scrubDate: $scrubDate)
                    .accessibilityIdentifier("myday-strip")
                chips(timeline)
                outsideNotes(timeline)
            }
        }
    }

    /// The overlay switches. Garmin's curves appear only on a day that has them, and each is named for its
    /// source: NOOP's stress and Garmin's stress are never one curve.
    private func chips(_ timeline: DayTimeline) -> some View {
        LookFlowLayout(spacing: NoopMetrics.space2, lineSpacing: NoopMetrics.space2) {
            MyDayChip(title: timeline.garminStress.isEmpty ? "Stress" : "Stress \u{00B7} NOOP", systemImage: "bolt.heart",
                      isOn: showStress, identifier: "myday-chip-stress") { showStress.toggle() }
            if !timeline.garminStress.isEmpty {
                MyDayChip(title: "Stress \u{00B7} Garmin", systemImage: "bolt.heart", isOn: showGarminStress,
                          identifier: "myday-chip-garmin-stress") { showGarminStress.toggle() }
            }
            MyDayChip(title: "Steps", systemImage: "figure.walk", isOn: showSteps,
                      identifier: "myday-chip-steps") { showSteps.toggle() }
            if !timeline.energy.isEmpty {
                MyDayChip(title: "Energy", systemImage: "battery.75percent", isOn: showEnergy,
                          identifier: "myday-chip-energy") { showEnergy.toggle() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line under the switches for each outside curve that is on: what it is and where it came from, and
    /// Garmin's last recharge under the energy curve.
    @ViewBuilder
    private func outsideNotes(_ timeline: DayTimeline) -> some View {
        if showEnergy, !timeline.energy.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Energy is Garmin's Body Battery, 0 to 100.")
                    .accessibilityIdentifier("myday-energy-note")
                if let line = timeline.recharge?.text(clock: clockText) {
                    Text(line).accessibilityIdentifier("myday-recharge")
                }
            }
            .font(StrandFont.caption)
            .foregroundStyle(StrandPalette.textTertiary)
        }
        if showGarminStress, !timeline.garminStress.isEmpty {
            Text("Stress \u{00B7} Garmin is Garmin's own 0 to 100 read, a separate curve from NOOP's.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityIdentifier("myday-garmin-stress-note")
        }
        if showStress, timeline.stress.isEmpty, !timeline.garminStress.isEmpty {
            Text("NOOP has no stress read for this day. Garmin's is available under Stress \u{00B7} Garmin.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .accessibilityIdentifier("myday-stress-fallback")
        }
    }

    private func clockText(_ ts: Int) -> String {
        AppClock.hourMinuteFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    /// "14:32 · 142 bpm · Run" under the finger, or the day's heart-rate range at rest.
    private func readout(_ timeline: DayTimeline) -> String {
        let clock = AppClock.hourMinuteFormatter()
        guard let scrubDate else {
            let values = timeline.hr.map(\.bpm)
            guard let low = values.min(), let high = values.max() else { return String(localized: "No heart rate yet") }
            return String(localized: "\(Int(low.rounded()))\u{2013}\(Int(high.rounded())) bpm today")
        }
        var parts = [clock.string(from: scrubDate)]
        if let p = MyDayStripGeometry.nearest(to: Int(scrubDate.timeIntervalSince1970), in: timeline.hr) {
            parts.append("\(Int(p.bpm.rounded())) bpm")
        }
        let ts = Int(scrubDate.timeIntervalSince1970)
        if showEnergy, let point = Self.nearest(to: ts, in: timeline.energy) { parts.append("Energy \(Int(point.value.rounded()))") }
        if showGarminStress, let point = Self.nearest(to: ts, in: timeline.garminStress) {
            parts.append("Garmin stress \(Int(point.value.rounded()))")
        }
        if let e = Self.event(at: scrubDate, in: timeline) { parts.append(e.title) }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// The outside reading nearest `ts`, if one lies within half an hour.
    private static func nearest(to ts: Int, in points: [DayTimeline.SeriesPoint], limit: Int = 1800) -> DayTimeline.SeriesPoint? {
        guard let best = points.min(by: { abs($0.ts - ts) < abs($1.ts - ts) }), abs(best.ts - ts) <= limit else { return nil }
        return best
    }

    /// The event a time falls inside, else the timed event that started most recently before it. When several
    /// contain it, the most specific wins: a workout over the walking stretch it sits inside.
    static func event(at date: Date, in timeline: DayTimeline) -> DayTimeline.Event? {
        func rank(_ kind: DayTimeline.Kind) -> Int {
            switch kind {
            case .workout: return 0
            case .sleep, .nap: return 1
            case .detected: return 2
            case .planned: return 3
            case .noData: return 4
            case .stepsBurst: return 6
            default: return 5
            }
        }
        let timed = timeline.events.filter { !$0.isUntimed }
        let inside = timed.filter { e in
            guard let end = e.end else { return false }
            return e.start <= date && date <= end
        }
        if let best = inside.min(by: { rank($0.kind) < rank($1.kind) }) { return best }
        return timed.filter { $0.start <= date }.max(by: { $0.start < $1.start })
    }

    // MARK: States

    private var loadingCard: some View {
        NoopCard {
            VStack(spacing: NoopMetrics.rowSpacing) {
                ProgressView().controlSize(.large)
                Text("Loading the day…")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
        .accessibilityIdentifier("myday-loading")
    }

    private var emptyHint: String {
        isToday
            ? String(localized: "Sync your strap to fill the day in. Anything on your plan is listed below.")
            : String(localized: "No heart rate or activity was recorded. Anything on your plan is listed below.")
    }

    private func emptyState(_ timeline: DayTimeline) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: NoopMetrics.space2) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
                Text("Nothing recorded for this day")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Text(emptyHint)
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("myday-empty")
    }

    // MARK: Event list

    @ViewBuilder
    private func eventList(_ timeline: DayTimeline) -> some View {
        // A day with no heart rate at all is one whole-day gap; the empty-state card above already says so.
        let events = timeline.hasHeartRate ? timeline.events : timeline.events.filter { $0.kind != .noData }
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: NoopMetrics.gap) {
                SectionHeader("Timeline", overline: "Newest first", trailing: "\(events.count)")
                NoopCard(padding: NoopMetrics.space3) {
                    VStack(spacing: 0) {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            MyDayRow(event: event, text: rowText(event), isHighlighted: event.id == highlightedId,
                                     opens: opens(event),
                                     onOpen: { open(event) },
                                     onSave: { save(event) }, onDismiss: { dismiss(event) })
                                .id(event.id)
                            if index < events.count - 1 { Divider().overlay(StrandPalette.hairline) }
                        }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("myday-list")
        }
    }

    /// The row's subtitle with the figures that depend on the reader's units.
    private func rowText(_ event: DayTimeline.Event) -> String {
        var text = event.subtitle
        if event.kind == .workout, let meters = event.metrics.distanceM, meters > 0 {
            text += " \u{00B7} " + UnitFormatter.distanceFromMeters(meters, system: distanceSystem)
        }
        if event.kind == .weighIn, let kg = event.metrics.weightKg, unitSystem == .imperial {
            text = String(format: "%.1f lb", UnitFormatter.kgToPounds(kg))
        }
        if event.continuesFromPreviousDay { text += " \u{00B7} " + String(localized: "from yesterday") }
        if event.continuesToNextDay { text += " \u{00B7} " + String(localized: "continues tomorrow") }
        return text
    }

    private func opens(_ event: DayTimeline.Event) -> Bool {
        switch event.route {
        case .none: return false
        case .workout(let key): return loaded?.workoutRows[key] != nil
        case .sleep: return true
        case .ride: return MyDayRideScreen.make != nil
        }
    }

    private func open(_ event: DayTimeline.Event) {
        switch event.route {
        case .none: break
        case .workout(let key):
            if let row = loaded?.workoutRows[key] { sheet = .workoutDetail(row) }
        case .sleep:
            sheet = .sleep
        case .ride(let id):
            if MyDayRideScreen.make != nil { sheet = .ride(id) }
        }
    }

    // MARK: Detected workouts

    private func save(_ event: DayTimeline.Event) {
        guard let suggestion = loaded?.detected[event.id] else { return }
        Task {
            _ = await repo.saveDetectedWorkout(suggestion)
            await repo.refresh()
        }
    }

    private func dismiss(_ event: DayTimeline.Event) {
        guard let suggestion = loaded?.detected[event.id] else { return }
        repo.dismissDetectedSuggestion(suggestion)
        Task { await reload() }
    }

    // MARK: Add

    private var addMenu: some View {
        Menu {
            Button { sheet = .addWorkout } label: { Label("Workout", systemImage: "figure.run") }
            Button { sheet = napSeed() } label: { Label("Nap", systemImage: "moon.zzz") }
            if isToday {
                Button {
                    CaffeineLogStore.shared.log(at: Date(), mg: nil)
                } label: { Label("Caffeine now", systemImage: "cup.and.saucer") }
                if hydrationEnabled {
                    Button {
                        Task { _ = await repo.logHydration(amountMl: 250) }
                    } label: { Label("Water, 250 ml", systemImage: "drop") }
                }
            }
        } label: {
            Label("Add", systemImage: "plus.circle.fill")
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.accent)
        }
        .accessibilityIdentifier("myday-add")
    }

    /// A 30-minute nap window on the shown day: just before now today, 14:00 on an earlier day.
    private func napSeed() -> Sheet {
        let now = Int(Date().timeIntervalSince1970)
        if isToday { return .addNap(bedTs: now - 45 * 60, wakeTs: now - 15 * 60) }
        let calendar = Calendar.current
        let afternoon = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: dayStart) ?? dayStart
        let bed = Int(afternoon.timeIntervalSince1970)
        return .addNap(bedTs: bed, wakeTs: bed + 30 * 60)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .addWorkout:
            ManualWorkoutSheet(editing: nil) { row, replacing in
                Task {
                    await repo.saveManualWorkout(row, replacing: replacing)
                    await intelligence.analyzeRecent()
                    await reload()
                }
            }
        case .addNap(let bedTs, let wakeTs):
            SleepTimeEditor(bedTs: bedTs, wakeTs: wakeTs,
                            title: "Add a nap",
                            blurb: "Pick when the nap started and ended. NOOP stages it from your data as its own session, separate from the night's sleep.",
                            bedLabel: "Nap started", wakeLabel: "Nap ended") { startTs, endTs in
                await repo.addManualNap(startTs: startTs, endTs: endTs)
                await intelligence.analyzeRecent()
                await repo.refresh()
            }
        case .workoutDetail(let row):
            NavigationStack {
                WorkoutDetailView(row: row)
                    .environmentObject(repo)
            }
            #if os(iOS)
            .noopSheetPresentation(largeFirst: true)
            #else
            .frame(width: 620, height: 720)
            #endif
        case .sleep:
            NavigationStack {
                SleepView()
                    .environmentObject(repo)
                    .toolbar {
                        ToolbarItem { Button("Done") { self.sheet = nil } }
                    }
            }
            #if os(iOS)
            .noopSheetPresentation(largeFirst: true)
            #else
            .frame(width: 620, height: 720)
            #endif
        case .ride(let id):
            if let make = MyDayRideScreen.make { make(id) }
        }
    }
}

// MARK: - Chip

private struct MyDayChip: View {
    let title: LocalizedStringKey
    let systemImage: String
    let isOn: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(StrandFont.footnote)
                .foregroundStyle(isOn ? StrandPalette.surfaceBase : StrandPalette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? StrandPalette.accent : StrandPalette.surfaceInset, in: Capsule())
                .overlay(Capsule().stroke(isOn ? StrandPalette.accent : StrandPalette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Row

private struct MyDayRow: View {
    let event: DayTimeline.Event
    let text: String
    let isHighlighted: Bool
    let opens: Bool
    let onOpen: () -> Void
    let onSave: () -> Void
    let onDismiss: () -> Void

    private var tint: Color { MyDayStyle.color(event.kind) }

    var body: some View {
        HStack(alignment: .top, spacing: NoopMetrics.space3) {
            timeColumn
                .frame(width: 52, alignment: .leading)
            Image(systemName: MyDayStyle.symbol(event))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(StrandFont.headline)
                    .foregroundStyle(event.kind == .noData ? StrandPalette.textSecondary : StrandPalette.textPrimary)
                if !text.isEmpty {
                    Text(text)
                        .font(StrandFont.footnote)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !event.sources.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(event.sources, id: \.self) { source in
                            SourceBadge(LocalizedStringKey(source.badge), tint: StrandPalette.textSecondary)
                        }
                    }
                }
                actions
            }
            Spacer(minLength: 0)
            if opens {
                Image(systemName: "chevron.right")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .padding(.top, 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, NoopMetrics.space2)
        .padding(.horizontal, NoopMetrics.space1)
        .background(isHighlighted ? tint.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if opens { onOpen() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(opens ? .isButton : [])
        .accessibilityIdentifier("myday-row-\(event.id)")
    }

    @ViewBuilder private var actions: some View {
        switch event.kind {
        case .detected:
            HStack(spacing: NoopMetrics.space2) {
                Button(action: onSave) { Label("Save as workout", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .controlSize(.small)
                    .accessibilityIdentifier("myday-save-\(event.id)")
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("myday-dismiss-\(event.id)")
            }
            .padding(.top, 2)
        case .nap:
            Button(action: onOpen) { Label("Open", systemImage: "arrow.up.right") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var timeColumn: some View {
        let clock = AppClock.hourMinuteFormatter()
        if event.isUntimed {
            Text("All day").strandOverline()
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(clock.string(from: event.start))
                    .font(StrandFont.captionNumber)
                    .foregroundStyle(StrandPalette.textPrimary)
                if let end = event.end {
                    Text(clock.string(from: end))
                        .font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
        }
    }

    private var accessibilityText: String {
        let clock = AppClock.hourMinuteFormatter()
        var parts = [event.title]
        if event.isUntimed {
            parts.append(String(localized: "all day"))
        } else if let end = event.end {
            parts.append("\(clock.string(from: event.start)) \u{2013} \(clock.string(from: end))")
        } else {
            parts.append(clock.string(from: event.start))
        }
        if !text.isEmpty { parts.append(text) }
        if !event.sources.isEmpty { parts.append(event.sources.map(\.badge).joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}
