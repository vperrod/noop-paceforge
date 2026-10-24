import SwiftUI
import StrandDesign

/// PaceForge "Coach": the daily brief, Coach's Take, the latest weekly review and the chat tail.
struct PFCoachView: View {
    let snapshot: PFSnapshot
    @EnvironmentObject private var model: PFModel
    @EnvironmentObject private var noopCoach: AICoachEngine
    @State private var draft = ""
    @State private var sending = false
    @State private var chatStatus: String?
    @State private var monthlyRead: PFMonthlyCoachRead?
    @State private var selectedWorkout: PFWorkout?

    private var coach: PFCoach { snapshot.coach }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coach.brief != nil || coach.take != nil {
                todayReadCard(brief: coach.brief, take: coach.take)
            }
            if let review = coach.weeklyReview { weeklyReviewCard(review) }
            if let monthlyRead { monthlyReviewCard(monthlyRead) }
            if !pendingWorkoutReviews.isEmpty { pendingWorkoutReviewsCard }
            if !recentWorkoutReads.isEmpty { workoutReadsCard }
            chatCard
        }
        .task(id: snapshot.todayISO) { await loadMonthlyRead() }
        .task(id: noopCoach.pendingPrompt) {
            guard let prompt = noopCoach.pendingPrompt, !prompt.isEmpty else { return }
            let sessionID = noopCoach.pendingSessionID
            noopCoach.pendingPrompt = nil
            noopCoach.pendingSessionID = nil
            await sendMessage(prompt, sessionID: sessionID)
        }
        .sheet(item: $selectedWorkout) { workout in
            PFResultsSheet(workout: workout, snapshot: snapshot, onAskCoach: { sessionID in
                noopCoach.pendingSessionID = sessionID
                noopCoach.pendingPrompt = "Explain this workout's review and what it means for my training plan."
            })
                .environmentObject(model)
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
                ForEach(pendingWorkoutReviews, id: \.id) { item in
                    let activity = snapshot.activities[item.id]
                    if let activity {
                        Button {
                            selectedWorkout = pendingWorkout(item, activity)
                        } label: {
                            pendingWorkoutStatusRow(item, activity: activity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this workout and its Coach review status.")
                    } else {
                        pendingWorkoutStatusRow(item, activity: nil)
                    }
                    .accessibilityIdentifier("coach-workout-status-\(item.id)")
                }
            }
        }
        .accessibilityIdentifier("coach-workout-review-status")
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

    // MARK: Today's Coach read

    private func todayReadCard(brief: PFBrief?, take: PFTake?) -> some View {
        PFCard(title: String(localized: "Today's read"), icon: "sparkles", trailing: {
            HStack(spacing: 6) {
                if let date = brief?.date {
                    Text(PFFormat.shortDate(date)).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                }
                if let take { readinessChip(take) }
            }
        }) {
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
        .accessibilityIdentifier("coach-todays-read")
    }

    @ViewBuilder private func readinessChip(_ take: PFTake) -> some View {
        if let score = take.readinessScore {
            let band = take.readinessBand ?? ""
            PFChip(text: "Readiness \(Safe.int(score)) \u{00B7} \(band)",
                   color: band == "low" ? PFColor.critical : band == "moderate" ? PFColor.warning : PFColor.positive)
        }
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
                            .font(.system(size: 14))
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

    // MARK: Chat

    private var chatCard: some View {
        PFCard("Talk to your coach", icon: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(coach.chat) { PFChatBubble(turn: $0) }

                HStack(spacing: 10) {
                    TextField("Ask your coach", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
                        .accessibilityIdentifier("pf-chat-input")
                    Button {
                        Task { await sendMessage() }
                    } label: {
                        if sending {
                            ProgressView().tint(StrandPalette.accent).frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(StrandPalette.accent)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(sending || !CoachBriefScheduler.coachMasterEnabled
                              || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message to Coach")
                    .accessibilityIdentifier("pf-chat-send")
                }

                if let chatStatus {
                    Text(chatStatus)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-chat-status")
                } else {
                    Text("Your Coach uses your latest synced PaceForge and NOOP data.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @MainActor private func sendMessage(_ suppliedMessage: String? = nil, sessionID: String? = nil) async {
        let message = (suppliedMessage ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }
        guard CoachBriefScheduler.coachMasterEnabled else {
            chatStatus = "Coach is turned off in Settings."
            return
        }
        let previousCoachTurn = coach.chat.last(where: { $0.role == "coach" })?.ts
        sending = true
        chatStatus = nil
        defer { sending = false }
        do {
            let result = try await PFAPI.postCoachMessage(message, sessionID: sessionID)
            guard (200..<300).contains(result.status) else {
                chatStatus = PFJ(data: result.data)["message"].text
                    ?? "The server refused the message (HTTP \(result.status))."
                return
            }
            draft = ""
            await model.refresh()
            for _ in 0..<30 {
                if let reply = model.snapshot?.coach.chat.last(where: { $0.role == "coach" }),
                   reply.ts != previousCoachTurn {
                    return
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await model.refresh()
            }
            chatStatus = "Your message was sent; the Coach is still working. Refresh to check for the reply."
        } catch {
            chatStatus = "Couldn't send your message. \(PFAPI.failureDetail(error))"
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

private struct PFChatBubble: View {
    let turn: PFChatTurn

    private var isAthlete: Bool { turn.role == "athlete" }

    var body: some View {
        HStack {
            if isAthlete { Spacer(minLength: 40) }
            Text(turn.text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isAthlete ? StrandPalette.accent.opacity(0.22) : StrandPalette.surfaceInset)
                )
            if !isAthlete { Spacer(minLength: 40) }
        }
    }
}
