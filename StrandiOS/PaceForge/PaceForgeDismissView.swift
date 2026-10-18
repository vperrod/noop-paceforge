import SwiftUI
import StrandDesign

// "Not today" on the PaceForge cards: a small x on the corner of each card, a menu with "Hide until it changes" and
// "Snooze until tomorrow", and a "Hidden cards" row at the bottom of Today to bring one back. The rules and the
// hash are in PaceForgeDismiss.swift (unit-tested); this file is the store, the card texts that get hashed and the
// views. Kept on the phone only; the server's dismissed.json is honoured as well.

// MARK: - The cards

/// The cards that can be hidden. The raw value is the key stored locally and matched against dismissed.json.
enum PFCardKind: String, CaseIterable {
    case todaysCall = "todays-call"
    case dayInReview = "day-in-review"
    case todaySoFar = "today-so-far"
    case brief
    case easyMode = "easy-mode"
    case raceWeek = "race-week"
    case feel
    case alerts
    case scores
    case whatChanged = "what-changed"
    case readiness
    case nextRace = "next-race"
    case standing
    case behaviour
    case nextBestAction = "next-best-action"

    var title: String {
        switch self {
        case .todaysCall: return "Today's call"
        case .dayInReview: return "Day in review"
        case .todaySoFar: return "Today so far"
        case .brief: return "Daily briefing"
        case .easyMode: return "Easy mode"
        case .raceWeek: return "Race week"
        case .feel: return "How do you feel?"
        case .alerts: return "Alerts"
        case .scores: return "Today's scores"
        case .whatChanged: return "What changed"
        case .readiness: return "Readiness"
        case .nextRace: return "Next race"
        case .standing: return "Where you stand"
        case .behaviour: return "Behaviour impact"
        case .nextBestAction: return "Next best action"
        }
    }
}

/// A card as it reads right now: what gets hashed to decide whether it is the same card as the one hidden.
struct PFCardRef {
    let kind: PFCardKind
    let text: String
}

/// A hidden card and the list that hides it.
struct PFHiddenCard: Identifiable {
    let card: PFCardRef
    let source: PFDismissSource
    var id: String { card.kind.rawValue }
}

/// The text of each card, built from the same fields the card draws. Times that tick (the clock marker, "updated
/// 08:12") are left out, so a card does not come back just because a minute went by.
enum PFCardText {
    static func todaySoFar(_ s: PFSnapshot) -> String {
        let m = PFTodaySoFar.make(from: s)
        return "\(m.planned)|\(m.done)|\(m.pending.joined(separator: ","))|\(m.sleepText ?? "")"
    }

    static func brief(_ b: PFDailyBrief) -> String {
        var lines: [String] = [b.headline]
        lines += [b.changes, b.bodyState, b.training, b.recent].compactMap { $0 }
        lines += b.notes + b.outlook + b.focus
        return lines.joined(separator: "\n")
    }

    static func easyMode(_ e: PFEasyMode) -> String {
        var lines: [String] = []
        if let mode = e.mode { lines.append("\(mode.level)|\(mode.label)|\(mode.summary ?? "")|\(mode.day ?? 0)") }
        lines += e.pending.map { "\($0.proposalId)|\($0.title)" }
        return lines.joined(separator: "\n")
    }

    static func raceWeek(_ w: PFRaceWeek) -> String {
        ([w.summaryLine] + w.notes).joined(separator: "\n")
    }

    static func feel(_ f: PFFeelSummary) -> String {
        "\(f.date ?? "")|\(f.answered)|\(f.feel ?? 0)|\(f.sentence ?? "")"
    }

    static func alerts(_ list: [PFAlert]) -> String {
        list.map { "\($0.id)|\($0.severity)|\($0.title)|\($0.body ?? "")" }.joined(separator: "\n")
    }

    static func scores(_ t: PFToday) -> String {
        let recovery = t.recovery.map { String(Safe.int($0.score)) } ?? ""
        let strain = t.strain.map { PFFormat.oneDecimal($0.value) } ?? ""
        let sleep = t.sleep.map { String(Safe.int($0.score)) } ?? ""
        return "\(recovery)|\(strain)|\(sleep)"
    }

    static func whatChanged(_ c: PFWhatChanged) -> String {
        var lines: [String] = [c.summary ?? ""]
        lines += c.metrics.map { "\($0.id)|\($0.value.map { PFNumber.trimmedOne($0) } ?? "")|\($0.direction)" }
        return lines.joined(separator: "\n")
    }

    static func readiness(_ r: PFReadiness) -> String {
        var lines: [String] = []
        if let train = r.answers?.train { lines.append("train|\(train.level.word)|\(train.reason ?? "")") }
        if let hard = r.answers?.trainHard { lines.append("hard|\(hard.level.word)|\(hard.reason ?? "")") }
        lines.append("\(r.agreement ?? "")|\(r.coachNote ?? "")")
        return lines.joined(separator: "\n")
    }

    /// Today's call hashes the verdict and the two bands, not the scores, so a score moving a point does not bring it back.
    static func todaysCall(_ call: PFTodaysCall) -> String {
        "\(call.call.chipText)|\(call.charge?.band ?? "")|\(call.readiness?.band ?? "")|\(call.agreement ?? "")"
    }

    static func dayInReview(_ review: PFDayReview) -> String {
        "\(review.outcomeText)|\(review.tonight?.bedtime ?? "")|\(review.tomorrow?.name ?? "")"
    }

    static func nextRace(_ race: PFNextRace) -> String { "\(race.name)|\(race.date)|\(race.daysOut)" }

    static func standing(_ s: PFStanding) -> String {
        let lines = s.summaryLines
        return "\(s.isApplicable)|\(s.summary?.counts.map { String($0) }.joined(separator: ",") ?? "")|\(lines.strongest ?? "")|\(lines.focus ?? "")"
    }

    static func behaviour(_ b: PFBehaviourImpact) -> String {
        (b.topLines + b.items.compactMap { $0.line }).joined(separator: "\n")
    }

    /// The cards that are hidden right now, and which list hides each.
    static func hidden(_ s: PFSnapshot, local: [PFDismissal]) -> [PFHiddenCard] {
        all(s).compactMap { card in
            guard let source = PFDismissLogic.hiddenBy(key: card.kind.rawValue, text: card.text, today: s.todayISO,
                                                        local: local, server: s.dismissed) else { return nil }
            return PFHiddenCard(card: card, source: source)
        }
    }

    /// Every card the snapshot has right now, in screen order.
    static func all(_ s: PFSnapshot) -> [PFCardRef] {
        var out: [PFCardRef] = []
        if let call = s.dailyIntel?.call { out.append(PFCardRef(kind: .todaysCall, text: todaysCall(call))) }
        if let review = s.dailyIntel?.review, PFIntelClock.isEvening() {
            out.append(PFCardRef(kind: .dayInReview, text: dayInReview(review)))
        }
        out.append(PFCardRef(kind: .todaySoFar, text: todaySoFar(s)))
        if let brief = s.today.brief { out.append(PFCardRef(kind: .brief, text: Self.brief(brief))) }
        if let easy = s.easyMode, !easy.isIdle { out.append(PFCardRef(kind: .easyMode, text: easyMode(easy))) }
        if let week = s.raceWeek { out.append(PFCardRef(kind: .raceWeek, text: raceWeek(week))) }
        if let f = s.feel { out.append(PFCardRef(kind: .feel, text: feel(f))) }
        if !s.alerts.isEmpty { out.append(PFCardRef(kind: .alerts, text: alerts(s.alerts))) }
        if s.today.recovery != nil || s.today.strain != nil || s.today.sleep != nil {
            out.append(PFCardRef(kind: .scores, text: scores(s.today)))
        }
        if let changes = s.whatChanged { out.append(PFCardRef(kind: .whatChanged, text: whatChanged(changes))) }
        if let r = s.readiness { out.append(PFCardRef(kind: .readiness, text: readiness(r))) }
        if let standing = s.standing, standing.hasContent { out.append(PFCardRef(kind: .standing, text: Self.standing(standing))) }
        if let race = s.today.nextRace, s.raceWeek == nil { out.append(PFCardRef(kind: .nextRace, text: nextRace(race))) }
        if let b = s.behaviour { out.append(PFCardRef(kind: .behaviour, text: behaviour(b))) }
        if let next = s.insightsV2?.todayCard { out.append(PFCardRef(kind: .nextBestAction, text: next.dismissText)) }
        return out
    }
}

// MARK: - Store

/// The phone's hidden cards. A UI-test fixture starts empty on every launch and never touches the real list.
@MainActor
final class PFDismissStore: ObservableObject {
    static let shared = PFDismissStore()

    @Published private(set) var local: [PFDismissal]
    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if PFAPI.isFixture, let suite = UserDefaults(suiteName: "noop.paceforge.dismissed.fixture") {
            suite.removePersistentDomain(forName: "noop.paceforge.dismissed.fixture")
            self.defaults = suite
        } else {
            self.defaults = .standard
        }
        local = PFDismissStorage.load(defaults: self.defaults, today: PFAPI.todayISO)
    }

    func hide(_ kind: PFCardKind, text: String, mode: PFDismissMode, today: String) {
        local = PFDismissLogic.dismissing(local, key: kind.rawValue, text: text, mode: mode, today: today, now: Date())
        PFDismissStorage.save(local, defaults: defaults)
    }

    func restore(_ kind: PFCardKind) {
        local = PFDismissLogic.restoring(local, key: kind.rawValue)
        PFDismissStorage.save(local, defaults: defaults)
    }
}

// MARK: - Views

/// A card with the "Not today" corner menu, or nothing while the card is hidden.
struct PFDismissable<Content: View>: View {
    let kind: PFCardKind
    let text: String
    let snapshot: PFSnapshot
    private let content: Content
    @ObservedObject private var store = PFDismissStore.shared

    init(_ kind: PFCardKind, text: String, snapshot: PFSnapshot, @ViewBuilder content: () -> Content) {
        self.kind = kind
        self.text = text
        self.snapshot = snapshot
        self.content = content()
    }

    var body: some View {
        if PFDismissLogic.isHidden(key: kind.rawValue, text: text, today: snapshot.todayISO,
                                   local: store.local, server: snapshot.dismissed) {
            EmptyView()
        } else {
            content.overlay(alignment: .topTrailing) { menu }
        }
    }

    private var menu: some View {
        Menu {
            Button {
                store.hide(kind, text: text, mode: .untilChanged, today: snapshot.todayISO)
            } label: {
                Label("Hide until it changes", systemImage: "eye.slash")
            }
            Button {
                store.hide(kind, text: text, mode: .untilTomorrow, today: snapshot.todayISO)
            } label: {
                Label("Snooze until tomorrow", systemImage: "moon.zzz")
            }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .offset(x: 13, y: -13)
        .accessibilityLabel("Not today")
        .accessibilityHint("Hides \(kind.title) until it changes, or until tomorrow")
        .accessibilityIdentifier("pf-dismiss-\(kind.rawValue)")
    }
}

/// "Hidden cards" at the bottom of Today: how many are hidden right now, and a list to show them again.
struct PFHiddenCardsRow: View {
    let snapshot: PFSnapshot
    @ObservedObject private var store = PFDismissStore.shared
    @State private var isShowing = false

    var body: some View {
        let items = PFCardText.hidden(snapshot, local: store.local)
        if !items.isEmpty {
            Button { isShowing = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text("Hidden cards")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(items.count)")
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hidden cards, \(items.count)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pf-hidden-cards")
            .sheet(isPresented: $isShowing) {
                PFHiddenCardsSheet(snapshot: snapshot, store: store)
            }
        }
    }
}

struct PFHiddenCardsSheet: View {
    let snapshot: PFSnapshot
    @ObservedObject var store: PFDismissStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = PFCardText.hidden(snapshot, local: store.local)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PFParagraph("A card hidden until it changes comes back when its text changes. A snoozed card comes back tomorrow.")
                    ForEach(items) { item in
                        HStack(alignment: .center, spacing: 10) {
                            Text(item.card.kind.title)
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            if item.source == .local {
                                Button("Show again") { store.restore(item.card.kind) }
                                    .buttonStyle(.bordered)
                                    .tint(StrandPalette.accent)
                                    .accessibilityIdentifier("pf-restore-\(item.card.kind.rawValue)")
                            } else {
                                Text("Hidden in PaceForge")
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textTertiary)
                                    .accessibilityIdentifier("pf-hidden-server-\(item.card.kind.rawValue)")
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(StrandPalette.surfaceInset))
                    }
                    if items.isEmpty {
                        PFParagraph("Nothing is hidden.")
                            .accessibilityIdentifier("pf-hidden-empty")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Hidden cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-hidden-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .containerIdentifier("pf-hidden-sheet")
    }
}
