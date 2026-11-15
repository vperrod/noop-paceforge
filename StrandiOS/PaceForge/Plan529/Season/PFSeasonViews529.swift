import SwiftUI
import StrandDesign

// S1, the Season chip of the Plan tab: the season bar and where you are in it, the next race with its own dates, the races after it, the
// hours of every week planned and done, and three rows (add a race, programmes on the web, how your plan is built).

/// Race week, when it is race week: the card the old Season chip carried, at the top.
struct PFSeasonRaceWeek529: View {
    var body: some View {
        PFSnapshotHost(drawsChrome: false, content: { snapshot in
            if let week = snapshot.raceWeek {
                return AnyView(PFDismissable(.raceWeek, text: PFCardText.raceWeek(week), snapshot: snapshot) {
                    PFRaceWeekCard(week: week, todayISO: snapshot.todayISO)
                })
            }
            return AnyView(EmptyView())
        })
    }
}

struct PFSeasonContent529: View {
    let doc: PFSeasonDoc

    var body: some View {
        let races = doc.races ?? []
        VStack(alignment: .leading, spacing: 12) {
            PFSeasonBarCard529(doc: doc)
            if let next = races.first {
                PFNextRaceCard529(race: next)
                if races.count > 1 { PFLaterRacesCard529(after: next, races: Array(races.dropFirst())) }
            } else {
                PFDocPlaceholder529(kind: .empty, emptyTitle: "No races yet",
                                    emptyText: "Add a race and the coach builds the season around it.")
            }
            PFSeasonHoursCard529(hours: doc.hours)
        }
    }
}

// MARK: The bar

struct PFSeasonBarCard529: View {
    let doc: PFSeasonDoc

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = doc.title { PFOver529(text: title) }
            PFPhaseBar529(segments: doc.bar ?? [])
            PFPhaseLegend529()
            if let now = doc.now {
                VStack(alignment: .leading, spacing: 3) {
                    if let line = now.line {
                        Text(line)
                            .font(LookFont.text(15, weight: .bold))
                            .foregroundStyle(NoopLook.textPrimary)
                    }
                    if let detail = now.detail {
                        Text(detail)
                            .font(LookFont.text(14))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("season-now")
            }
        }
        .planCard529()
        .containerIdentifier("season-bar")
    }
}

// MARK: Races

func pfPriorityPill529(_ race: PFSeasonDoc.Race, short: Bool = false) -> PFPill529 {
    if race.prioritySet == true, let priority = race.priority, !priority.isEmpty {
        return PFPill529(text: short ? priority : "Priority \(priority)", tone: .blue)
    }
    return PFPill529(text: short ? "not set" : "Priority not set", tone: .amber)
}

@MainActor func pfOpenRace529(_ date: String?) {
    guard let date else { return }
    PFPlan529Router.shared.sheet = .race(date: date)
}

struct PFNextRaceCard529: View {
    let race: PFSeasonDoc.Race

    private var heading: String {
        [race.short ?? race.name, race.dayLabel].compactMap { $0 }.joined(separator: " \u{00B7} ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(heading)
                    .lookCaps(14)
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                pfPriorityPill529(race)
            }
            if let sub = race.sub {
                Text(sub)
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
            }
            if let bar = race.bar, !bar.isEmpty { PFPhaseBar529(segments: bar) }
            if let lines = race.phaseLines, !lines.isEmpty {
                LookFlowLayout(spacing: 12, lineSpacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(LookFont.text(12.5))
                            .foregroundStyle(NoopLook.textSecondary)
                    }
                }
            }
            if let note = race.priorityNote {
                Text(note)
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                PFPillButton529(title: race.prioritySet == true ? "Change priority" : "Set priority", isMain: race.prioritySet != true) {
                    pfOpenRace529(race.date)
                }
                .accessibilityIdentifier("season-set-priority")
                PFPillButton529(title: "Open race") { pfOpenRace529(race.date) }
                    .accessibilityIdentifier("season-open-race")
            }
        }
        .planCard529()
        .containerIdentifier("season-next-race")
    }
}

struct PFLaterRacesCard529: View {
    let after: PFSeasonDoc.Race
    let races: [PFSeasonDoc.Race]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "After \(after.short ?? after.name ?? "the next race")")
                .padding(.bottom, 4)
            ForEach(Array(races.enumerated()), id: \.offset) { index, race in
                if index > 0 { PFDivider529() }
                Button { pfOpenRace529(race.date) } label: {
                    PFRow529(lead: race.dayLabel, title: race.short ?? race.name ?? "Race", sub: race.sub,
                             trailingPill: pfPriorityPill529(race, short: true))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("season-race-\(race.date ?? String(index))")
            }
        }
        .planCard529()
        .containerIdentifier("season-later-races")
    }
}

// MARK: Hours by week

struct PFSeasonHoursCard529: View {
    let hours: PFSeasonDoc.Hours?

    private let barHeight: CGFloat = 64

    private func height(_ value: Double?, top: Double) -> CGFloat {
        guard let value, value > 0 else { return 0 }
        return max(3, CGFloat(value / top) * barHeight)
    }

    private func label(_ week: PFSeasonDoc.Week) -> String {
        var parts = ["Week \(week.label ?? week.week ?? "")"]
        if let planned = week.planned { parts.append("planned \(PFHours529.text(planned))") }
        if let done = week.done { parts.append("done \(PFHours529.text(done))") }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        if let hours, let weeks = hours.weeks, !weeks.isEmpty {
            let top = max(1, hours.max ?? 0, weeks.map { max($0.planned ?? 0, $0.done ?? 0) }.max() ?? 0)
            VStack(alignment: .leading, spacing: 8) {
                PFOver529(text: "Hours by week \u{00B7} planned and done")
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        HStack(alignment: .bottom, spacing: 2) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(PFColor.sky, lineWidth: 1.5)
                                .frame(height: height(week.planned, top: top))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(week.race == true ? PFColor.critical : NoopLook.textTertiary)
                                .frame(height: height(week.done, top: top))
                        }
                        .frame(maxWidth: .infinity, minHeight: barHeight, maxHeight: barHeight, alignment: .bottom)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(label(week))
                    }
                }
                HStack(spacing: 4) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        Text(week.label ?? "")
                            .font(LookFont.text(9.5))
                            .foregroundStyle(NoopLook.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                if let note = hours.note {
                    Text(note)
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .planCard529()
            .containerIdentifier("season-hours")
        }
    }
}

// MARK: Three rows

struct PFSeasonLinks529: View {
    let programmes: PFSeasonDoc.Programmes?

    @State private var addsRace = false

    private var webRoute: String {
        let route = String((programmes?.webRoute ?? "").drop(while: { $0 == "#" }))
        return route.isEmpty ? PFWebPage.plan : route
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { addsRace = true } label: {
                PFRow529(title: "Add a race", trailing: "+")
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("season-add-race")
            PFDivider529()
            PFWebPageRow(title: "Programmes", detail: programmes?.line ?? "Start or change one on the web",
                         icon: "calendar.badge.plus", route: webRoute, identifier: "season-programmes")
            PFDivider529()
            Button { PFPlan529Router.shared.sheet = .planSettings } label: {
                PFRow529(title: "How your plan is built", showsChevron: true)
                    .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("season-how-built")
        }
        .planCard529(padding: 0)
        .containerIdentifier("season-links")
        .sheet(isPresented: $addsRace) {
            PFEventsSheet().environmentObject(PFUnified.model)
        }
    }
}
