import SwiftUI
import StrandDesign

/// What a row needs from the page around it.
struct PFWeekHooks529 {
    var openResults: (PFResultsTarget529) -> Void
    var openSession: (String) -> Void
    var openSwap: (PFSwapTarget529) -> Void
    var askCoach: (String) -> Void
}

/// The two sessions of a day an "Overlaps" chip is about.
struct PFOverlapTarget543: Identifiable, Equatable {
    let week: String
    let day: PFPlanWeekDoc.Day
    let item: PFPlanWeekDoc.Item

    var id: String {
        PFNeedsStrip543.overlapKey(date: day.date, title: item.title, overlap: item.overlap ?? PFPlanWeekDoc.Overlap())
    }
}

/// One day of the week: its title and every session of the day as a row of one or two lines (build 543, drawing 3.1).
struct PFWeekDay529: View {
    let week: String
    let day: PFPlanWeekDoc.Day
    let isToday: Bool
    let hooks: PFWeekHooks529
    /// False in a finished week: its sessions are history, so no change is offered.
    var allowsEdits = true

    @ObservedObject private var model = PFUnified.model
    @State private var overlap: PFOverlapTarget543?

    private var items: [PFPlanWeekDoc.Item] { day.items ?? [] }
    private var keyedItems: [(key: String, item: PFPlanWeekDoc.Item)] {
        items.enumerated().map { offset, item in
            (item.sessionId ?? "\(day.date ?? "")-\(item.kind ?? "")-\(item.raceDate ?? String(offset))", item)
        }
    }
    /// Bike rides of the day from the ride metrics: they are not planned sessions, so they sit beside the rows as before.
    private var rides: [PFRide] { model.snapshot?.rides(on: day.date ?? "") ?? [] }

    private var countText: String? {
        let sessions = items.filter { PFPlanRow543.isSession($0) }.count
        guard sessions > 0 else { return nil }
        return sessions == 1 ? "1 session" : "\(sessions) sessions"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.title ?? day.dow ?? "")
                    .font(PFPlanFont543.text(17, weight: .bold))
                    .foregroundStyle(isToday ? PFWeekColor529.teal : NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if isToday { Text("Today").font(PFPlanFont543.text(15, weight: .semibold)).foregroundStyle(PFWeekColor529.teal) }
                if let tag = day.tag, !tag.isEmpty {
                    Text(tag).font(PFPlanFont543.text(15, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let countText {
                    Text(countText).font(PFPlanFont543.text(15, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                }
            }
            .padding(.horizontal, 2)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            // Keyed by the session id (a race by its date, else the position): a row keeps its own state when its neighbour changes.
            ForEach(keyedItems, id: \.key) { entry in
                PFWeekItemCard529(week: week, day: day, item: entry.item, isToday: isToday, hooks: hooks, allowsEdits: allowsEdits,
                                  onOverlap: { overlap = PFOverlapTarget543(week: week, day: day, item: entry.item) })
                    .id(entry.key)
            }
            if let snapshot = model.snapshot {
                ForEach(rides) { PFRideRow(ride: $0, snapshot: snapshot) }
            }
            if items.isEmpty && rides.isEmpty { PFWeekSub529(text: "Nothing planned.") }
        }
        .containerIdentifier("plan529-day-\(day.date ?? "")")
        .background { Color.clear.sheet(item: $overlap) { PFOverlapSheet543(target: $0) } }
    }
}

/// A session, a race or a rest day as a row: the title, one line of what it is, and its badges. Everything else is one tap away on the
/// session's own screen.
struct PFWeekItemCard529: View {
    let week: String
    let day: PFPlanWeekDoc.Day
    let item: PFPlanWeekDoc.Item
    let isToday: Bool
    let hooks: PFWeekHooks529
    var allowsEdits = true
    var onOverlap: () -> Void = {}

    @ObservedObject private var model = PFUnified.model
    private let hiding = PFHiding()

    private var kind: String { item.kind ?? "session" }
    private var date: String { day.date ?? "" }
    private var key: String { item.sessionId ?? "\(date)-\(kind)" }
    private var isDone: Bool { PFPlanRow543.isDone(item) }
    private var isCoach: Bool { PFPlanRow543.isCoach(item) }
    /// The overlap unless the athlete chose "Keep both" for this pair on this day.
    private var shownOverlap: PFPlanWeekDoc.Overlap? {
        guard let overlap = item.overlap else { return nil }
        return UserDefaults.standard.bool(forKey: PFOverlap543.keptKey(date: day.date, title: item.title, overlap: overlap)) ? nil : overlap
    }
    private var opensSomething: Bool { kind != "rest" && (item.activityId != nil || item.sessionId != nil) }

    var body: some View {
        if kind == "rest" {
            restRow
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: open) { mainRow }
                    .buttonStyle(.plain)
                    .disabled(!opensSomething)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(PFPlanRow543.sentence(item, dow: day.dow))
                    .accessibilityHint(opensSomething ? "Opens the session" : "")
                    .accessibilityIdentifier(openIdentifier)
                if kind == "session", !isDone { PFWatchChip529(sessionID: item.sessionId).padding(.horizontal, 12) }
                if let overlap = shownOverlap { overlapButton(overlap) }
            }
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
            .overlay(alignment: .leading) {
                if isCoach {
                    Rectangle().fill(PFPlanCoachEdge543.color).frame(width: 5).accessibilityHidden(true)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous))
            .containerIdentifier("plan529-item-\(key)")
        }
    }

    // MARK: Rows

    private var mainRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title ?? "")
                    .font(PFPlanFont543.text(17, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if opensSomething {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            if let line = summaryLine {
                Text(hiding.text(line))
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-summary-\(key)")
            }
            let badges = rowBadges
            if !badges.isEmpty { PFPlanBadgeRow543(badges: badges) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .padding(.leading, isCoach ? 4 : 0)
        .contentShape(Rectangle())
    }

    private var restRow: some View {
        Text(item.title ?? "Rest day")
            .font(PFPlanFont543.text(15, weight: .regular))
            .foregroundStyle(NoopLook.textSecondary)
            .padding(.horizontal, 2)
            .accessibilityIdentifier("plan529-item-\(key)")
    }

    /// A session's one line; a race's result; the finished race's time.
    private var summaryLine: String? {
        if kind == "race" {
            if let result = item.result, let time = result.time { return [time, result.delta].compactMap { $0 }.joined(separator: " \u{00B7} ") }
            return item.raceDate.map { "Race on \(PFFormat.dayTitle($0))" }
        }
        return PFPlanRow543.summary(item)
    }

    /// The badges of a row without the overlap chip: that one is its own button.
    private var rowBadges: [PFPlanBadge543] {
        PFPlanRow543.badges(item).filter { $0.tone != .overlap }
    }

    private func overlapButton(_ overlap: PFPlanWeekDoc.Overlap) -> some View {
        Button(action: onOverlap) {
            HStack(spacing: 6) {
                PFPlanBadgeView543(badge: PFPlanBadge543(text: PFPlanRow543.overlapText(overlap), tone: .overlap))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(PFPlanRow543.overlapText(overlap)). Opens the overlap.")
        .accessibilityIdentifier("plan529-overlap-\(key)")
    }

    /// A session keeps the identifier its row had (`pf-workout-<id>`), a race too (`pf-week-race-<date>`).
    private var openIdentifier: String {
        if kind == "race" { return "pf-week-race-\(item.raceDate ?? date)" }
        return item.sessionId.map { "pf-workout-\($0)" } ?? "plan529-open-\(key)"
    }

    /// A session opens its own screen (planned or finished); a race or a recording without a session opens the results sheet.
    private func open() {
        if kind == "session", let id = item.sessionId {
            hooks.openSession(id)
        } else if let id = item.activityId {
            hooks.openResults(PFResultsTarget529(id: id, title: item.title, date: date, isRace: kind == "race"))
        }
    }
}
