import SwiftUI
import StrandDesign

// Blocks Today adds from the PaceForge snapshot, each its own host so Today's body does not observe the model: Weight vs goal (My Dashboard).
// Every block draws nothing when the data behind it is missing.

// MARK: - Weight vs goal

/// The newest weight reading Today knows (Apple Health, the scale through PaceForge, ...), with who supplied it and its day.
struct PFNewestWeight: Equatable {
    let kg: Double
    let source: String
    /// yyyy-MM-dd.
    let day: String
}

/// Today's "Weight vs goal": the newest weight reading (dated, with its source) against the weight goal, the gap and the weekly trend.
/// One tap opens Health on the Body chip. Draws nothing without a weight goal, or while Hide numbers hides body weight.
struct PFTodayWeightGoalHost: View {
    /// What Today's Weight tile reads. PaceForge's own last reading is used only when it is the newer one (or Today has none).
    var newest: PFNewestWeight?

    var body: some View {
        PFSnapshotHost(drawsChrome: false, content: { snapshot in
            AnyView(PFTodayWeightGoalCard(progress: snapshot.bodyProgress, newest: newest))
        })
    }
}

private struct PFTodayWeightGoalCard: View {
    let progress: PFBodyProgress?
    let newest: PFNewestWeight?
    private let hiding = PFHiding()

    private var goal: PFProgressGoal? {
        guard let goal = progress?.goals.first(where: { $0.metric == "weight_kg" }), goal.target != nil else { return nil }
        return goal
    }

    /// Today's newest reading, unless PaceForge's last reading is from a later day.
    private func usable(_ newest: PFNewestWeight?) -> PFNewestWeight? {
        guard let newest else { return nil }
        if let latest = progress?.latestReadingDate, String(latest.prefix(10)) > newest.day { return nil }
        return newest
    }

    var body: some View {
        if let goal, let target = goal.target, !hiding.hides(.body) {
            let fresh = usable(newest)
            let reading = fresh?.kg ?? goal.lastReading ?? goal.current7d
            Button { PFDeepLink.open(.body) } label: {
                PFCard("Weight vs goal", icon: "scalemass") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(reading.map { value($0, goal.unit) } ?? "\u{2014}")
                                .font(LookFont.text(28, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                                .accessibilityIdentifier("today-weight-goal-current")
                            Text("goal \(value(target, goal.unit))")
                                .font(LookFont.text(13, weight: .medium))
                                .foregroundStyle(NoopLook.textSecondary)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NoopLook.textTertiary)
                                .accessibilityHidden(true)
                        }
                        if let reading { line(gapText(reading: reading, target: target, goal: goal)) }
                        if let trend = trendText(goal) { line(trend) }
                        Text(sourceText(goal, fresh: fresh))
                            .font(LookFont.text(11.5, weight: .medium))
                            .foregroundStyle(NoopLook.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-weight-goal")
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(LookFont.text(13, weight: .medium))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func value(_ v: Double, _ unit: String) -> String {
        PFFormat.oneDecimal(v) + (unit.isEmpty ? "" : " \(unit)")
    }

    /// Distance to the target, in the direction the goal runs (down when the start was above it).
    private func gapText(reading: Double, target: Double, goal: PFProgressGoal) -> String {
        let goesDown = (goal.startValue ?? reading) >= target
        let toGo = goesDown ? reading - target : target - reading
        if toGo <= 0 { return "Target reached" }
        let by = goal.targetDate.map { " \u{00B7} by \(PFFormat.shortDate($0))" } ?? ""
        return "\(value(toGo, goal.unit)) to go\(by)"
    }

    /// "Trend 0.3 kg a week down (on track)", from PaceForge's own weekly rate.
    private func trendText(_ goal: PFProgressGoal) -> String? {
        guard let rate = goal.actualPerWeek, rate != 0 else { return nil }
        let word = rate < 0 ? "down" : "up"
        let status = goal.status == "insufficient_data" ? "" : " (\(PFFormat.words(goal.status)))"
        return "Trend \(value(abs(rate), goal.unit)) a week \(word)\(status)"
    }

    private func sourceText(_ goal: PFProgressGoal, fresh: PFNewestWeight?) -> String {
        if let fresh { return "Latest reading \(PFFormat.shortDate(fresh.day)) \u{00B7} \(fresh.source)" }
        let kind = goal.lastReading != nil ? "Last reading" : "7-day average"
        let date = progress?.latestReadingDate.map { " \(PFFormat.shortDate($0))" } ?? ""
        return "\(kind)\(date) \u{00B7} Hume scale, via PaceForge"
    }
}

// MARK: - Today so far (what was recorded today)

/// My Day's Today so far card: the plan line, the mini strip and Open My Day, then what the watch recorded today, each row with its
/// numbers and a tap to its results.
struct PFTodayRecordedHost: View {
    var body: some View {
        PFSnapshotHost(drawsChrome: false, content: { snapshot in AnyView(PFTodaySoFarCard(snapshot: snapshot)) })
            .containerIdentifier("today-so-far")
    }
}

// MARK: - Bookend row (morning read, evening review)

/// One row at the top of My Day: in the evening the Day in review summary (when today's review exists), otherwise the morning read, which
/// is the daily report row. Each opens what its own block opens: the review's full card, or the daily report. The two blocks lower on
/// Today stay where they are. Draws nothing when neither exists.
struct PFTodayBookendRow: View {
    @ObservedObject private var intel = PFDailyIntelStore.shared
    @ObservedObject private var reports = PFReportsStore.shared
    @State private var showReview = false
    private let hiding = PFHiding()

    private var review: PFDayReview? {
        guard let current = intel.intel, PFIntelClock.isEvening(), current.isCurrent(for: PFAPI.todayISO),
              current.item(PFIntelID.dayInReview) != nil else { return nil }
        return current.review
    }

    var body: some View {
        // Re-read every minute (and on return to the foreground, when the timeline resumes), so the row turns into the day in review
        // when the evening starts without the screen being reopened.
        TimelineView(.everyMinute) { _ in
            Group {
                if let review {
                    Button { showReview = true } label: {
                        rowContent(icon: "moon.stars", title: "DAY IN REVIEW", detail: reviewLine(review))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-bookend")
                } else if reports.showsReports, let report = reports.latestDaily {
                    NavigationLink(value: TabRoute.reports(PFReportKind.daily.rawValue)) {
                        rowContent(icon: "text.book.closed", title: "MORNING READ", detail: PFReportFreshness.dateLine(report))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("today-bookend")
                }
            }
        }
        // On the outer view, not inside the branch, so the sheet survives the row changing under it.
        .sheet(isPresented: $showReview) { reviewSheet }
        .task { await intel.refreshIfStale() }
    }

    private func reviewLine(_ review: PFDayReview) -> String {
        var parts = [review.outcomeText.capitalized]
        if let sentence = review.sentence { parts.append(hiding.text(sentence)) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func rowContent(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(StrandFont.scaled(16, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lookCaps(12.5)
                    .foregroundStyle(NoopLook.textPrimary)
                Text(detail)
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(StrandFont.scaled(12, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .contentShape(Rectangle())
    }

    private var reviewSheet: some View {
        NavigationStack {
            ScrollView {
                PFDayReviewStoreHost()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Day in review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showReview = false }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
