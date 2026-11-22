import SwiftUI
import StrandDesign

/// R1: a finished week is its report. One verdict, your races, planned against done, recovery from each device in its own chart, three
/// short findings, the decision for next week, the links to the long tables, and the week's sessions as one line each.
struct PFWeekReport529: View {
    let week: String
    let doc: PFPlanWeekDoc
    let header: PFWeekHeader529
    let hooks: PFWeekHooks529
    let goToWeek: (String) -> Void
    @ObservedObject var decisions: PFWeekDecisions529

    private let hiding = PFHiding()
    private var report: PFPlanWeekDoc.Report? { doc.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            if let review = report?.review, !review.isEmpty { PFReviewLinkRow530(week: week) }
            if let races = report?.races, !races.isEmpty { racesCard(races) }
            plannedAgainstDone
            if let nights = report?.nights, let series = nights.series, !series.isEmpty { nightsCard(nights, series) }
            findings
            if let next = report?.nextWeek { NextWeekCard529(next: next, decisions: decisions, goToWeek: goToWeek, hooks: hooks) }
            links
        }
    }

    // MARK: Verdict

    private var top: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PFWeekPills529(pills: pills)
            if let verdict = report?.verdict, !verdict.isEmpty {
                Text(hiding.text(verdict))
                    .font(PFPlanFont543.text(22, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-verdict")
            }
            if let story = report?.story, !story.isEmpty {
                PFWeekBody529(text: story).accessibilityIdentifier("plan529-story")
            }
            ForEach((report?.insights ?? []).indices, id: \.self) { index in
                insight((report?.insights ?? [])[index], index: index)
            }
        }
        .pfWeekCard()
    }

    private func insight(_ item: PFPlanWeekDoc.Insight, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text = item.text, !text.isEmpty { PFWeekBody529(text: text) }
        }
        .accessibilityIdentifier("plan529-insight-\(index)")
    }

    private var pills: [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { out.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if report?.readyAt != nil { out.append(("Report ready", PFWeekColor529.teal)) }
        return out
    }

    // MARK: Races

    private func racesCard(_ races: [PFPlanWeekDoc.Race]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            PFWeekOverline529(text: "Your races")
            ForEach(races.indices, id: \.self) { index in
                if index > 0 { Divider().overlay(NoopLook.divider) }
                raceRow(races[index])
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-races")
    }

    private func raceRow(_ race: PFPlanWeekDoc.Race) -> some View {
        Button {
            if let id = race.activityId {
                hooks.openResults(PFResultsTarget529(id: id, title: race.name, date: race.date, isRace: true))
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(race.day ?? "")
                    .pfCaps(12, weight: .semibold)
                    .foregroundStyle(NoopLook.textSecondary)
                    .frame(minWidth: 54, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.name ?? "").font(PFPlanFont543.text(15, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
                    if let sub = race.sub { PFWeekSub529(text: sub) }
                }
                Spacer(minLength: 6)
                Text(race.time ?? "").font(PFPlanFont543.text(15, weight: .bold)).foregroundStyle(NoopLook.textPrimary)
                if race.activityId != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(race.activityId == nil)
        .accessibilityIdentifier("plan529-race-\(race.activityId ?? race.date ?? "")")
    }

    // MARK: Planned against done

    private var plannedAgainstDone: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "The week, planned against done")
            PFWeekStrip529(days: doc.strip ?? [])
            if let line = report?.plannedDone?.line {
                LookFlowLayout(spacing: 12, lineSpacing: 4) {
                    Text(hiding.text(line)).font(PFPlanFont543.text(12.5, weight: .semibold)).foregroundStyle(NoopLook.textPrimary)
                    ForEach((report?.plannedDone?.facts ?? []).indices, id: \.self) { index in
                        Text(hiding.text((report?.plannedDone?.facts ?? [])[index]))
                            .font(PFPlanFont543.text(12.5, weight: .regular))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                }
                .accessibilityIdentifier("plan529-planned-done")
            }
            if let versus = report?.plannedDone?.vsPrev { PFWeekSub529(text: versus) }
            sessionRows
        }
        .pfWeekCard()
        .containerIdentifier("plan529-planned-against-done")
    }

    /// Each session of the week once, the coach's first, with where it ended up as a word. The week's workouts are not repeated as cards.
    @ViewBuilder private var sessionRows: some View {
        let rows = PFReportSessions543.rows(doc)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { offset, row in
                    if offset > 0 { PFDivider529() }
                    Button {
                        if let id = row.sessionID { hooks.openSession(id) }
                        else if let activity = row.activityID { hooks.openResults(PFResultsTarget529(id: activity, title: row.title, date: nil)) }
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                    .font(PFPlanFont543.text(16, weight: .semibold))
                                    .foregroundStyle(NoopLook.textPrimary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                if row.isCoach {
                                    Text(PFPlanRow543.coachSource)
                                        .font(PFPlanFont543.text(15, weight: .regular))
                                        .foregroundStyle(PFColor.violet)
                                }
                            }
                            Spacer(minLength: 6)
                            Text(row.state)
                                .font(PFPlanFont543.text(16, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NoopLook.textSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.sentence)
                    .accessibilityIdentifier("plan529-report-session-\(row.sessionID ?? row.activityID ?? String(offset))")
                }
            }
            .containerIdentifier("plan529-report-sessions")
        }
    }

    // MARK: Nights

    private func nightsCard(_ nights: PFPlanWeekDoc.Nights, _ series: [PFPlanWeekDoc.Series]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(series.indices, id: \.self) { index in
                PFWeekNights529(series: series[index], labels: nights.labels ?? [], showsDays: index == series.count - 1)
            }
            if let note = nights.note { PFWeekSub529(text: note) }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-nights")
    }

    // MARK: Findings

    private var findings: some View {
        VStack(alignment: .leading, spacing: 12) {
            finding("Went well", PFWeekColor529.teal, report?.wentWell ?? [], id: "well")
            finding("Held you back", PFWeekColor529.amber, report?.heldBack ?? [], id: "held")
            if let text = report?.notToDo, !text.isEmpty {
                finding("One thing not to do", PFWeekColor529.red, [text], id: "not")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-findings")
    }

    @ViewBuilder private func finding(_ title: String, _ tint: Color, _ texts: [String], id: String) -> some View {
        if !texts.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).pfCaps(10.5, weight: .semibold).foregroundStyle(tint)
                ForEach(texts.indices, id: \.self) { index in
                    Text(hiding.text(texts[index]))
                        .font(PFPlanFont543.text(14, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plan529-finding-\(id)")
        }
    }

    // MARK: Links and workouts

    private var links: some View {
        VStack(spacing: 0) {
            link(report?.detail?.numbersTitle ?? "The numbers, session by session", id: "plan529-link-numbers")
            Divider().overlay(NoopLook.divider)
            link(report?.detail?.expertsTitle ?? "What each expert read", id: "plan529-link-experts")
        }
        .pfWeekCard()
    }

    private func link(_ title: String, id: String) -> some View {
        NavigationLink(value: TabRoute.reports("\(PFReportKind.weekly.rawValue):\(week)")) {
            HStack {
                Text(title).font(PFPlanFont543.text(15, weight: .medium)).foregroundStyle(NoopLook.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

/// One device's nights: bars coloured by band, the value under each bar.
struct PFWeekNights529: View {
    let series: PFPlanWeekDoc.Series
    let labels: [String]
    let showsDays: Bool

    private let hiding = PFHiding()
    private var values: [Double?] { series.values ?? [] }
    private var bands: [String] { series.bands ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PFWeekOverline529(text: series.title ?? series.source ?? "")
                .accessibilityIdentifier("plan529-nights-title-\((series.source ?? "device").lowercased())")
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(values.indices, id: \.self) { index in
                    bar(index)
                }
            }
            .frame(height: 52, alignment: .bottom)
            row { index in
                Text(valueText(index)).font(PFPlanFont543.text(10, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
            }
            if showsDays && !labels.isEmpty {
                row { index in
                    Text(index < labels.count ? labels[index] : "")
                        .font(PFPlanFont543.text(10, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan529-nights-\((series.source ?? "device").lowercased())")
    }

    private func bar(_ index: Int) -> some View {
        let value = values[index]
        let top = series.max ?? 100
        let height = CGFloat(max(0, min(1, (value ?? 0) / max(top, 1)))) * 44
        let band = index < bands.count ? bands[index] : ""
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(value == nil ? NoopLook.track : PFWeekColor529.band(band))
            .frame(maxWidth: .infinity)
            .frame(height: max(4, height))
    }

    private func row<Content: View>(@ViewBuilder _ cell: @escaping (Int) -> Content) -> some View {
        HStack(spacing: 5) {
            ForEach(values.indices, id: \.self) { index in
                cell(index).frame(maxWidth: .infinity)
            }
        }
    }

    private func valueText(_ index: Int) -> String {
        guard let value = values[index] else { return "\u{2013}" }
        return hiding.shown(String(Int(value.rounded())), .scores)
    }
}

/// The decision for next week: its summary and Accept next week (every change of that week), Look at it, Talk to the coach.
struct NextWeekCard529: View {
    let next: PFPlanWeekDoc.NextWeek
    @ObservedObject var decisions: PFWeekDecisions529
    let goToWeek: (String) -> Void
    let hooks: PFWeekHooks529

    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Next week")
            if let summary = next.summary { PFWeekBody529(text: summary) }
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                if (next.changes ?? 0) > 0 {
                    PFWeekButton529(title: "Accept next week", isProminent: true, isDisabled: decisions.isBusy,
                                    identifier: "plan529-accept-next") {
                        Task { await acceptNextWeek() }
                    }
                }
                PFWeekButton529(title: "Open the plan", identifier: "plan529-look-next") {
                    if let week = next.week { goToWeek(week) }
                }
                PFWeekButton529(title: "Talk to the coach", identifier: "plan529-talk-next") {
                    hooks.askCoach("About next week (\(next.week ?? "")): \(next.summary ?? "") What do you recommend, and what happens if I change it?")
                }
            }
            if let note { PFWeekSub529(text: note).accessibilityIdentifier("plan529-accept-next-note") }
            if let failure = decisions.failure {
                Text(failure)
                    .font(PFPlanFont543.text(12.5, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .accessibilityIdentifier("plan529-accept-next-failed")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-next-week")
    }

    /// Accepts every change of next week's document, in turn.
    @MainActor private func acceptNextWeek() async {
        guard let week = next.week, let doc = await PFWeekFetch529.week(week) else {
            note = "Next week could not be read. Try again."
            return
        }
        let ids = (doc.changes ?? []).compactMap { $0.id }
        guard !ids.isEmpty else {
            note = "Nothing waits for you in next week."
            return
        }
        await decisions.acceptAll(ids)
        if decisions.failure == nil { note = ids.count == 1 ? "Accepted 1 change." : "Accepted \(ids.count) changes." }
    }
}
