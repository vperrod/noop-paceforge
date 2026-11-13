import SwiftUI
import StrandDesign

/// PaceForge "Coach", the Read chip: the plan proposals waiting (one row to them), the page note, today's read in full, the Expert
/// reading, what waits on the athlete (one row that opens the Needs you sheet), the Monthly coach review, the workout review status
/// and the recent workout reads. The Coach log follows it on the screen. The composer (Ask) is `PFCoachComposer`; the host that owns
/// the sheet and the week plan page the closures open is `CoachUnifiedView`.
struct PFCoachView: View {
    let snapshot: PFSnapshot
    /// The week plan page, where each pending proposal has its reasons and Accept / Reject.
    var onOpenProposals: () -> Void = {}
    /// The Needs you sheet (every question PaceForge is waiting on, answered in place).
    var onOpenNeedsYou: () -> Void = {}
    /// Moves the Coach to its Ask chip, where the chat and the composer are; run when a workout hands a question to the coach.
    var onAsk: () -> Void = {}
    @EnvironmentObject private var model: PFModel
    @EnvironmentObject private var noopCoach: AICoachEngine
    @State private var monthlyRead: PFMonthlyCoachRead?
    @State private var selectedWorkout: PFWorkout?

    private var coach: PFCoach { snapshot.coach }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            proposalsRow
            PFPageNote(key: "coach", alwaysOpen: true)
            if coach.brief != nil || coach.take != nil { todayRead(brief: coach.brief, take: coach.take) }
            PFExpertReadingHost()
            waitingRow
            if let monthlyRead { monthlyReviewCard(monthlyRead) }
            if !pendingWorkoutReviews.isEmpty { pendingWorkoutReviewsCard }
            if !recentWorkoutReads.isEmpty { workoutReadsCard }
        }
        .task(id: snapshot.todayISO) { await loadMonthlyRead() }
        .sheet(item: $selectedWorkout) { workout in
            PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: { sessionID in
                noopCoach.pendingSessionID = sessionID
                noopCoach.pendingPrompt = "Explain this workout's review and what it means for my training plan."
                onAsk()
            })
            .environmentObject(model)
        }
    }

    // MARK: Waiting on you

    /// The plan changes the coach proposes: the same row Today shows, at the top of the Read chip while any is pending.
    @ViewBuilder private var proposalsRow: some View {
        let proposals = PFWeekPlan.split(snapshot.needsYou).proposals
        if !proposals.isEmpty {
            PFProposalsRow(count: proposals.count, onOpen: onOpenProposals)
        }
    }

    /// How many questions PaceForge is waiting on him for (pace, effort, feel, a question); the row opens the Needs you sheet, which lists
    /// and answers every one of them. Plan proposals are not counted here: they have their own row above.
    @ViewBuilder private var waitingRow: some View {
        let count = PFWeekPlan.split(snapshot.needsYou).others.count
        if count > 0 {
            Button(action: onOpenNeedsYou) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                    Text("Waiting on you")
                        .lookCaps(12.5)
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineLimit(1)
                    PFChip(text: "\(count)", color: PFNeutral.other)
                        .fixedSize()
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach-waiting-on-you")
        }
    }

    // MARK: Today's read

    /// The whole brief and the whole take, as the card drew them before the redesign.
    private func todayRead(brief: PFBrief?, take: PFTake?) -> some View {
        PFCard(title: "Today's read", icon: "sparkles", trailing: {
            HStack(spacing: 6) {
                if let date = brief?.date {
                    Text(PFFormat.shortDate(date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let take { readinessChip(take) }
            }
        }) {
            fullRead(brief: brief, take: take)
        }
        .accessibilityIdentifier("coach-todays-read")
    }

    private func fullRead(brief: PFBrief?, take: PFTake?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let brief {
                Text(brief.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let sourceContext = brief.sourceContext {
                    Text(sourceContext)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array((brief.outlook ?? []).enumerated()), id: \.offset) { _, paragraph in
                    PFParagraph(paragraph)
                }
            }
            if let take {
                if brief != nil { Rectangle().fill(StrandPalette.hairline).frame(height: 1).padding(.vertical, 2) }
                Text(take.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                let limiters = take.limiters ?? []
                if !limiters.isEmpty {
                    Text("What is affecting you").strandOverline()
                    ForEach(Array(limiters.enumerated()), id: \.offset) { index, limiter in
                        PFLimiterRow(rank: index + 1, limiter: limiter)
                    }
                }
                let actions = take.weekActions ?? []
                if !actions.isEmpty {
                    Text("What to do next").strandOverline()
                    ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\u{2022}").foregroundStyle(StrandPalette.accent)
                            Text(action.action)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            if let generatedAt = snapshot.generatedAt {
                HStack(alignment: .firstTextBaseline) {
                    Text("PaceForge snapshot assembled")
                    Spacer(minLength: 8)
                    Text(PFFormat.relative(generatedAt) ?? generatedAt)
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            }
            if let offlineNote = model.offlineNote {
                Text(offlineNote)
                    .font(StrandFont.caption)
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private func readinessChip(_ take: PFTake) -> some View {
        if let score = take.readinessScore {
            let band = take.readinessBand ?? ""
            PFChip(text: "Readiness \(Safe.int(score)) \u{00B7} \(band)",
                   color: band == "low" ? PFColor.critical : band == "moderate" ? PFColor.warning : PFColor.positive)
        }
    }

    // MARK: Recent workout reads

    private var pendingWorkoutReviews: [PFAnalysisStatus] {
        snapshot.analysisStatuses.values
            .sorted { statusDate($0) > statusDate($1) }
            .prefix(5)
            .map { $0 }
    }

    private func statusDate(_ item: PFAnalysisStatus) -> String {
        snapshot.activities[item.id]?.startTime ?? item.id
    }

    private var pendingWorkoutReviewsCard: some View {
        PFCard("Workout reviews", icon: "clock") {
            VStack(alignment: .leading, spacing: 9) {
                ForEach<[PFAnalysisStatus], String, AnyView>(
                    pendingWorkoutReviews,
                    id: \PFAnalysisStatus.id
                ) { item in
                    workoutReviewStatusView(item)
                }
            }
        }
        .accessibilityIdentifier("coach-workout-review-status")
    }


    private func workoutReviewStatusView(_ item: PFAnalysisStatus) -> AnyView {
        let activity = snapshot.activities[item.id]
        let row: AnyView
        if let activity {
            row = AnyView(
                Button {
                    selectedWorkout = pendingWorkout(item, activity)
                } label: {
                    pendingWorkoutStatusRow(item, activity: activity)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this workout and its Coach review status.")
            )
        } else {
            row = AnyView(pendingWorkoutStatusRow(item, activity: nil))
        }
        return AnyView(row.accessibilityIdentifier("coach-workout-status-\(item.id)"))
    }

    private func pendingWorkoutStatusRow(_ item: PFAnalysisStatus, activity: PFActivity?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(activity?.name ?? activity?.type ?? (item.id.hasPrefix("bike:") ? "Bike ride" : "Workout"))
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Text(activity?.startTime.map { String($0.prefix(10)) }
                     ?? (item.id.hasPrefix("bike:") ? String(item.id.dropFirst(5).prefix(10)) : ""))
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            Text(item.reason ?? "Coach review is not available yet.")
                .font(StrandFont.caption)
                .foregroundStyle(item.status == "needs_input" ? PFColor.warning : StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pendingWorkout(_ item: PFAnalysisStatus, _ activity: PFActivity) -> PFWorkout {
        let date = activity.startTime.map { String($0.prefix(10)) } ?? snapshot.todayISO
        var result = PFWorkout(id: "coach-pending-\(item.id)", date: date, status: "done",
                               name: activity.name ?? activity.type, kind: activity.type, sport: activity.type,
                               durationMin: activity.durationS.map { $0 / 60 },
                               distanceKm: activity.distanceM.map { $0 / 1000 }, targetRpe: nil,
                               userRpe: snapshot.rpe[item.id], cadenceTarget: nil, description: nil, briefing: nil,
                               steps: [], exercises: [], compliance: nil, completionAnalysis: nil, notes: nil,
                               activityId: item.id)
        result.coachSessionID = snapshot.weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .first(where: { $0.activityId == item.id })?.coachSessionID
        return result
    }

    private var recentWorkoutReads: [(PFAnalysisRow, PFActivity)] {
        snapshot.analyses.values.compactMap { row in
            guard let activity = snapshot.activities[row.id], row.headline != nil else { return nil }
            return (row, activity)
        }
        .sorted { ($0.1.startTime ?? "") > ($1.1.startTime ?? "") }
        .prefix(5)
        .map { $0 }
    }

    private var workoutReadsCard: some View {
        PFCard("Recent workout reads", icon: "figure.run") {
            VStack(spacing: 0) {
                ForEach(Array(recentWorkoutReads.enumerated()), id: \.offset) { index, item in
                    let row = item.0
                    let activity = item.1
                    Button {
                        selectedWorkout = resultWorkout(row, activity)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(activity.name ?? activity.type ?? "Workout")
                                    .font(StrandFont.subhead.weight(.semibold))
                                    .foregroundStyle(StrandPalette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: 6)
                                Text(activity.startTime.map { String($0.prefix(10)) } ?? "")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                            }
                            Text(row.headline ?? "")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach-workout-read-\(row.id)")
                    if index < recentWorkoutReads.count - 1 {
                        Rectangle().fill(StrandPalette.hairline).frame(height: 1)
                    }
                }
            }
        }
        .accessibilityIdentifier("coach-workout-reads")
    }

    private func resultWorkout(_ row: PFAnalysisRow, _ activity: PFActivity) -> PFWorkout {
        let date = activity.startTime.map { String($0.prefix(10)) } ?? snapshot.todayISO
        var result = PFWorkout(id: "coach-\(row.id)", date: date, status: "done",
                               name: activity.name ?? activity.type, kind: activity.type, sport: activity.type,
                               durationMin: activity.durationS.map { $0 / 60 },
                               distanceKm: activity.distanceM.map { $0 / 1000 }, targetRpe: nil,
                               userRpe: snapshot.rpe[row.id], cadenceTarget: nil, description: nil, briefing: nil,
                               steps: [], exercises: [], compliance: nil, completionAnalysis: nil, notes: nil,
                               activityId: row.id)
        result.coachSessionID = snapshot.weeks.flatMap { $0.days }.flatMap { $0.workouts }
            .first(where: { $0.activityId == row.id })?.coachSessionID
        return result
    }

    // MARK: Monthly review

    private func monthlyReviewCard(_ read: PFMonthlyCoachRead) -> some View {
        PFCard("\(read.label) review", icon: "calendar") {
            VStack(alignment: .leading, spacing: 10) {
                if let overview = read.overview {
                    Text(overview).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                labeledReviewList("Went well", read.wentWell, icon: "checkmark.circle.fill", color: PFColor.positive)
                labeledReviewList("To improve", read.toImprove, icon: "arrow.up.right.circle.fill", color: PFColor.warning)
                if let focus = read.focus {
                    PFLabeled(label: "Focus this month", text: focus)
                }
                if let sourceContext = read.sourceContext {
                    DisclosureGroup("NOOP strap data used") {
                        Text(sourceContext)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .font(StrandFont.caption.weight(.semibold))
                    .tint(StrandPalette.accent)
                }
            }
        }
        .accessibilityIdentifier("coach-monthly-review")
    }

    @ViewBuilder private func labeledReviewList(_ title: String, _ rows: [String], icon: String, color: Color) -> some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).strandOverline()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Label(row, systemImage: icon)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .labelStyle(PFReviewLabelStyle(color: color))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func loadMonthlyRead() async {
        monthlyRead = nil
        guard let today = PFMonthlyCoachRead.day(snapshot.todayISO),
              let currentMonth = Calendar.current.dateInterval(of: .month, for: today)?.start,
              let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month], from: previousMonth)
        guard let year = parts.year, let month = parts.month else { return }
        let key = String(format: "%04d-%02d", year, month)
        guard let data = await model.monthlyCoachRead(monthKey: key),
              let read = PFMonthlyCoachRead(data: data, key: key) else { return }
        monthlyRead = read
    }

    // MARK: Weekly review

    func weeklyReviewCard(_ review: PFWeeklyReview) -> some View {
        PFCard(title: "Week review", icon: "calendar", trailing: {
            Text(PFFormat.span(review.period.start, review.period.end))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(review.headline)
                    .font(StrandFont.body.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let sourceContext = review.sourceContext {
                    DisclosureGroup("Evidence sources and dates") {
                        Text(sourceContext)
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 6)
                    }
                    .font(StrandFont.caption.weight(.semibold))
                    .tint(StrandPalette.accent)
                }

                if let fullRead = review.fullRead, !fullRead.isEmpty {
                    DisclosureGroup("Read the full week") {
                        PFMarkdown(text: fullRead)
                            .padding(.top, 8)
                    }
                    .font(StrandFont.subhead.weight(.semibold))
                    .tint(StrandPalette.accent)
                    .accessibilityIdentifier("coach-week-full-read")
                }

                if let planned = review.plannedRuns, let done = review.completedRuns {
                    HStack(spacing: 8) {
                        PFChip(text: "\(done) of \(planned) runs", color: done == planned ? PFColor.positive : PFColor.warning)
                        if let quality = review.qualityDone {
                            PFChip(text: "\(quality) quality", color: StrandPalette.accent)
                        }
                    }
                }

                ForEach(Array((review.sessions ?? []).enumerated()), id: \.offset) { _, s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: s.completed ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(s.completed ? PFColor.positive : PFColor.critical)
                            .font(StrandFont.scaled(14))
                        Text(s.name)
                            .font(StrandFont.subhead)
                            .foregroundStyle(StrandPalette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Text(PFFormat.shortDate(s.date))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }

                if let limiters = review.limiters, !limiters.isEmpty {
                    PFLabeled(label: "Limiters", text: limiters.joined(separator: " \u{00B7} "))
                }
                if let fatigue = review.fatigue, !fatigue.isEmpty {
                    PFLabeled(label: "Fatigue", text: fatigue.map(\.text).joined(separator: "\n"))
                }
                if let said = review.strengthSaid { PFLabeled(label: "Strength", text: said) }
                if let actions = review.thisWeek, !actions.isEmpty {
                    PFLabeled(label: "Next up", text: actions.joined(separator: "\n"))
                }
            }
        }
    }
}

private struct PFLimiterRow: View {
    let rank: Int
    let limiter: PFLimiter

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .font(StrandFont.rounded(13))
                .foregroundStyle(StrandPalette.accent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(StrandPalette.accent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(limiter.name)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text(limiter.area)
                        .font(StrandFont.overline)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                Text(limiter.evidence)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(limiter.recommendation)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(StrandPalette.surfaceInset))
            }
        }
    }
}

private struct PFMonthlyCoachRead {
    let label: String
    let overview: String?
    let wentWell: [String]
    let toImprove: [String]
    let focus: String?
    let sourceContext: String?

    init?(data: Data, key: String) {
        let root = PFJ(data: data)
        let narrative = root["narrative"]
        guard narrative.exists else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        let parsed = formatter.date(from: key)
        formatter.dateFormat = "MMMM yyyy"
        label = parsed.map(formatter.string(from:)) ?? key
        overview = narrative["overview"].text
        wentWell = narrative["went_well"].strings
        toImprove = narrative["to_improve"].strings
        focus = narrative["focus"].text
        let contexts = [root["source_context"]["noop"].text,
                        root["source_context"]["apple_health"].text]
            .compactMap { $0 }.filter { !$0.isEmpty }
        sourceContext = contexts.isEmpty ? nil : contexts.joined(separator: "\n\n")
    }

    static func day(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}

private struct PFReviewLabelStyle: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 8) {
            configuration.icon.foregroundStyle(color)
            configuration.title.fixedSize(horizontal: false, vertical: true)
        }
    }
}
