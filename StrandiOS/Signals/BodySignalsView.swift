import SwiftUI
import StrandDesign
import WhoopStore

// Body signals, opened from Today's call: what the strap, Garmin and PaceForge each say, side by side, with each one named. It
// chooses no winner, warns of nothing and changes no plan. A missing value stays missing.

struct BodySignalsReadings: Equatable {
    var whoopCharge: Double?
    var whoopHrv: Double?
    var garminReadiness: Double?
    var garminHrv: Double?

    @MainActor
    static func load(repo: Repository, snapshot: PFSnapshot, now: Date = Date()) async -> (day: String, readings: BodySignalsReadings) {
        #if DEBUG
        // `-BodySignalsFixture`: made-up readings for UI tests; Garmin's overnight HRV is left missing.
        if CommandLine.arguments.contains("-BodySignalsFixture") {
            return (snapshot.todayISO, BodySignalsReadings(whoopCharge: 71, whoopHrv: 46,
                                                           garminReadiness: garminReadiness(snapshot, day: snapshot.todayISO),
                                                           garminHrv: nil))
        }
        #endif
        let strap = Repository.resolveToday(days: repo.strapDays, logicalKey: Repository.logicalDayKey(now),
                                            localKey: Repository.localDayKey(now))
        let day = strap?.day ?? Repository.logicalDayKey(now)
        let garminHrv = await repo.series(key: "hrv", source: "paceforge-garmin", days: 3).last { $0.day == day }?.value
        return (day, BodySignalsReadings(whoopCharge: strap?.recovery, whoopHrv: strap?.avgHrv,
                                         garminReadiness: garminReadiness(snapshot, day: day), garminHrv: garminHrv))
    }

    /// Garmin's score from the readiness document the Readiness cards read, only when it is that day's.
    private static func garminReadiness(_ snapshot: PFSnapshot, day: String) -> Double? {
        guard snapshot.readiness?.date == day else { return nil }
        return snapshot.readiness?.sources.first { $0.source == "Garmin" }?.score
    }
}

struct BodySignalsScreen: View {
    let snapshot: PFSnapshot
    @EnvironmentObject private var repo: Repository
    @State private var loaded: (day: String, readings: BodySignalsReadings)?
    private let hiding = PFHiding()

    /// The check-in's own words, 1 to 5.
    private static let feelWords = ["awful", "poor", "okay", "good", "great"]

    private var signals: PFBodySignals? { snapshot.today.brief?.signals }

    private var feelText: String {
        guard let feel = snapshot.feel, feel.date == nil || feel.date == snapshot.todayISO, feel.answered,
              let value = feel.feel, (1...5).contains(value) else { return "Not answered" }
        return "\(value) of 5, \(Self.feelWords[value - 1])"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let loaded {
                recoveryCard(loaded.day, loaded.readings)
                hrvCard(loaded.readings)
                feelCard
                statusCard
                focusCard
                if let date = snapshot.today.brief?.date, date != snapshot.todayISO, signals != nil {
                    note("Training status and focus are from the briefing of \(PFFormat.shortDate(date)).")
                }
            }
        }
        .planScreen529(title: "Body signals", identifier: "body-signals")
        .task(id: repo.refreshSeq) { loaded = await BodySignalsReadings.load(repo: repo, snapshot: snapshot) }
    }

    private func recoveryCard(_ day: String, _ readings: BodySignalsReadings) -> some View {
        card("Recovery, \(TimingDates.dayMonth(day))", id: "signals-recovery") {
            number("Charge, current calculation", readings.whoopCharge, unit: "%", source: "WHOOP", id: "signals-whoop-charge",
                   color: readings.whoopCharge.map { NoopLook.chargeColor($0) })
            PFDivider529()
            number("Training readiness", readings.garminReadiness, unit: "", source: "Garmin", id: "signals-garmin-readiness")
        }
    }

    private func hrvCard(_ readings: BodySignalsReadings) -> some View {
        card("Heart rate variability", id: "signals-hrv") {
            number("Current calculation", readings.whoopHrv, unit: "ms", source: "WHOOP", id: "signals-whoop-hrv")
            PFDivider529()
            number("Overnight", readings.garminHrv, unit: "ms", source: "Garmin", id: "signals-garmin-hrv")
        }
    }

    private var feelCard: some View {
        card("How you feel", id: "signals-feel") {
            Text(feelText)
                .font(PFPlanFont543.text(17, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .padding(.vertical, 8)
                .accessibilityIdentifier("signals-feel-value")
        }
    }

    private var statusCard: some View {
        card("Training status", id: "signals-status") {
            words("Status", signals?.statusGarmin, source: "Garmin", id: "signals-status-garmin")
            PFDivider529()
            words("Load balance", signals?.statusPaceforge, source: "PaceForge", id: "signals-status-paceforge")
            note("PaceForge: your training-load balance and its 7-day trend. It measures something other than Garmin's status.")
        }
    }

    private var focusCard: some View {
        card("Training focus", id: "signals-focus") {
            words("Load focus", signals?.focusGarmin, source: "Garmin", id: "signals-focus-garmin")
            PFDivider529()
            words("Running time in zones", signals?.focusPaceforge, source: "PaceForge", id: "signals-focus-paceforge")
            note("PaceForge: running only.")
        }
    }

    private func card<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: title)
                .padding(.bottom, 4)
            content()
        }
        .planCard529(padding: 16)
        .containerIdentifier(id)
    }

    private func label(_ title: String, source: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PFSourceTag(source: source)
        }
    }

    private func number(_ title: String, _ value: Double?, unit: String, source: String, id: String,
                        color: Color? = nil) -> some View {
        let shown = value.map { String(Int($0.rounded())) } ?? "\u{2013}"
        return HStack(spacing: 8) {
            label(title, source: source)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(hiding.shown(shown, .scores))
                    .lookNumeral(34)
                    .foregroundStyle(value == nil ? NoopLook.textTertiary : (color ?? NoopLook.textPrimary))
                if value != nil, !unit.isEmpty {
                    Text(unit)
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(source): \(value == nil ? "missing" : "\(shown) \(unit)")")
        .accessibilityIdentifier(id)
    }

    private func words(_ title: String, _ value: String?, source: String, id: String) -> some View {
        HStack(spacing: 8) {
            label(title, source: source)
            Spacer(minLength: 8)
            Text(value.map { hiding.text($0) } ?? "\u{2013}")
                .font(PFPlanFont543.text(17, weight: .semibold))
                .foregroundStyle(value == nil ? NoopLook.textTertiary : NoopLook.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(source): \(value ?? "missing")")
        .accessibilityIdentifier(id)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(PFPlanFont543.text(12.5))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
