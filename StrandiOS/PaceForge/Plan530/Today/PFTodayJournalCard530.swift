import SwiftUI
import StrandDesign

/// The My Journal card on Today (screen 5a), under the overview card. It replaces the journal reminder card on the PaceForge Today:
/// the card is always on screen (it never disappears and never doubles with the old one), whatever state its document is in. The week
/// row is drawn from the document and the phone's own journal, so it is right while the document is loading, empty or could not be
/// fetched; only the line under it and the insights subtitle need the document.
/// A tap on a past day (or today) opens the existing journal on that day, to catch up, as the old card did.
struct PFTodayJournalCard530: View {
    @StateObject private var store = PFDocStore529<PFTodayJournal530>(path: PFDocPath529.journal)
    @StateObject private var session = PFJournalSession530()
    @EnvironmentObject private var repo: Repository
    @Environment(\.scenePhase) private var scenePhase
    /// Days of this week the phone's own journal holds an entry for.
    @State private var ownDays: Set<String> = []
    @State private var backfillDayOffset = 1
    @State private var showsBackfill = false

    var body: some View {
        // The loaders are their own always-present, zero-size view (see the overview card).
        ZStack {
            Color.clear
                .frame(width: 0, height: 0)
                .task { await store.refreshIfStale() }
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: repo.refreshSeq) {
                    await loadOwnDays()
                    await store.refreshIfStale()
                }
            card
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refreshIfStale() } }
        }
        .sheet(isPresented: $showsBackfill) {
            NavigationStack {
                ScrollView { InsightsView(embedded: true, backfillOnly: true, initialJournalDayOffset: backfillDayOffset) }
                    .navigationTitle("Back-fill journal")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { showsBackfill = false } } }
            }
        }
    }

    private var today: String { PFAPI.todayISO }

    private var card: some View {
        let doc = store.doc
        let week = PFTodayJournalLogic530.weekRow(doc, today: today, ownDays: ownDays)
        let target = PFTodayJournalLogic530.target(doc)
        let allDone = PFTodayJournalLogic530.isAllAnswered(doc)
        return VStack(alignment: .leading, spacing: 10) {
            header(target: target, dueWindow: (doc?.prompts ?? []).first { $0.state == "due" && ($0.open ?? 0) > 0 }?.window,
                   allDone: allDone)
            weekStrip(week)
            stateLine(doc)
            if let due = dueQuestions(doc) { answerRows(due) }
            insightsRow(doc)
        }
        .planCard529()
        .containerIdentifier("today-journal")
    }

    // MARK: Header

    private func header(target: PFTodayJournalTarget530, dueWindow: String?, allDone: Bool) -> some View {
        HStack(spacing: 8) {
            Text("My journal")
                .lookCaps(12.5)
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            NavigationLink(value: TabRoute.plan529(dueWindow == "afternoon" ? .journalAfternoon :
                                                    dueWindow == "morning" ? .journalMorning :
                                                    target == .morning ? .journalMorning : .journalEvening)) {
                PFPill529(text: allDone ? "Done" : "Fill out", tone: allDone ? .grey : .teal)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("today-journal-fill")
        }
    }

    // MARK: The week

    private func weekStrip(_ week: [PFTodayJournalLogic530.WeekDay]) -> some View {
        HStack(spacing: 4) {
            ForEach(week, id: \.date) { day in
                dayCell(day)
            }
        }
        .containerIdentifier("today-journal-week")
    }

    private func dayCell(_ day: PFTodayJournalLogic530.WeekDay) -> some View {
        let offset = PFFormat.daysBetween(day.date, today)
        let cell = VStack(spacing: 4) {
            Text(day.letter)
                .font(LookFont.text(10.5, weight: .semibold))
                .foregroundStyle(day.isToday ? NoopLook.textPrimary : NoopLook.textTertiary)
            if day.logged {
                Circle()
                    .fill(StrandPalette.accent)
                    .frame(width: 10, height: 10)
            } else if day.isToday {
                Text("now")
                    .font(LookFont.text(10.5, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
            } else {
                Text("\u{00B7}")
                    .font(LookFont.text(14))
                    .foregroundStyle(NoopLook.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        return Group {
            if day.isFuture {
                cell
            } else {
                cell.onTapGesture {
                    if day.isToday {
                        let route: Plan529Route = PFTodayJournalLogic530.target(store.doc) == .morning ? .journalMorning : .journalEvening
                        PFDeepLink529.open(.sheet(route))
                    } else {
                        backfillDayOffset = max(1, offset)
                        showsBackfill = true
                    }
                }
                    .accessibilityAddTraits(.isButton)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Self.weekdayName(day.date)), \(day.logged ? "logged" : day.isFuture ? "not yet" : "not logged")"))
        .accessibilityIdentifier("today-journal-day-\(offset)")
    }

    // MARK: The line and the insights

    private struct DueQuestions {
        let window: String
        let day: String
        let questions: [PFJournalDoc530.Question]
    }

    /// Only a due window draws answers. Waiting questions stay in their sheet until their alert moment.
    private func dueQuestions(_ doc: PFTodayJournal530?) -> DueQuestions? {
        guard let doc, let due = (doc.prompts ?? []).first(where: { $0.state == "due" && ($0.open ?? 0) > 0 }),
              let window = due.window else { return nil }
        let questions = (doc.list ?? []).filter { $0.window == window && $0.key != nil }.map { q in
            PFJournalDoc530.Question(key: q.key, label: q.label, prompt: q.prompt, hint: q.hint, kind: q.kind,
                                     window: q.window, about: q.about, yes: q.yes, no: q.no,
                                     state: nil, stateSource: nil, nYes: nil, nNo: nil)
        }
        guard !questions.isEmpty else { return nil }
        return DueQuestions(window: window,
                            day: PFJournalLogic530.behaviourDay(about: questions.first?.about, window: window, today: today),
                            questions: questions)
    }

    private func answerRows(_ due: DueQuestions) -> some View {
        let keys = due.questions.compactMap(\.key)
        let answers = session.staged(keys: keys, allowsPrevious: false)
        return VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: due.window == "morning" ? "About last night" : "For today")
            ForEach(Array(due.questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { PFDivider529() }
                PFJournalQuestionRow530(question: question, answer: answers[question.key ?? ""],
                    onChoose: { yes in
                        session.choose(key: question.key ?? "", kind: PFJournalLogic530.kind(question), yes: yes,
                                       keys: keys, allowsPrevious: false)
                        Task { await session.commit(repo: repo, day: due.day, keys: [question.key ?? ""], allowsPrevious: false) }
                    },
                    onNumber: { number in
                        session.setNumber(key: question.key ?? "", number, keys: keys, allowsPrevious: false)
                        Task { await session.commit(repo: repo, day: due.day, keys: [question.key ?? ""], allowsPrevious: false) }
                    },
                    onNote: { note in
                        session.setNote(key: question.key ?? "", note, keys: keys, allowsPrevious: false)
                        Task { await session.commit(repo: repo, day: due.day, keys: [question.key ?? ""], allowsPrevious: false) }
                    })
            }
            if due.window == "morning", !session.previous.isEmpty {
                Button("Use \(Self.weekdayName(PFJournalLogic530.addDays(due.day, -1) ?? due.day))'s answers") {
                    session.usePrevious = true
                    Task { await session.commit(repo: repo, day: due.day, keys: keys, allowsPrevious: true) }
                }
                .font(LookFont.text(13.5, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("today-journal-use-previous")
            }
            if !session.isSaving && !session.pending(keys: keys, allowsPrevious: false).isEmpty {
                Button(session.saveFailed ? "Retry saving" : "Save answers") {
                    Task { await session.commit(repo: repo, day: due.day, keys: keys, allowsPrevious: false) }
                }
                .font(LookFont.text(13.5, weight: .semibold))
                .foregroundStyle(StrandPalette.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("today-journal-save")
            }
            if session.saveFailed {
                Text("Answers could not be saved. Try again.")
                    .font(LookFont.text(12.5))
                    .foregroundStyle(PFColor.warning)
            }
        }
        .task(id: "\(due.window)|\(due.day)|\(keys.joined(separator: "|"))") {
            session.usePrevious = false
            await session.load(repo: repo, day: due.day, keys: keys, readsPrevious: due.window == "morning")
            if due.window == "evening" {
                session.prefillCaffeineFromHealthKit(day: due.day, keys: keys)
            }
        }
        .accessibilityIdentifier("today-journal-due-questions")
    }

    @ViewBuilder private func stateLine(_ doc: PFTodayJournal530?) -> some View {
        switch store.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading")
                    .font(LookFont.text(13))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            .accessibilityIdentifier("today-journal-loading")
        case .failed:
            HStack(spacing: 8) {
                Text("PaceForge could not be reached. The row shows what is on this phone.")
                    .font(LookFont.text(12.5))
                    .foregroundStyle(PFColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button { Task { await store.refresh() } } label: {
                    Text("Try again")
                        .font(LookFont.text(13, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("today-journal-retry")
            }
            .accessibilityIdentifier("today-journal-failed")
        case .empty:
            Text("Questions will appear here once PaceForge has today's journal.")
                .font(LookFont.text(13))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today-journal-empty")
        case .loaded:
            if let line = PFTodayJournalLogic530.line(doc, today: today) {
                aboutLine(line)
                if store.isStale { PFStaleNote529() }
            }
        }
    }

    /// "About Saturday: 4 answered ...": the day in bold, as drawn.
    private func aboutLine(_ line: String) -> some View {
        let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
        let text: Text
        if parts.count == 2 {
            text = Text(parts[0] + ":").fontWeight(.semibold).foregroundStyle(NoopLook.textPrimary)
                + Text(parts[1]).foregroundStyle(NoopLook.textSecondary)
        } else {
            text = Text(line).foregroundStyle(NoopLook.textSecondary)
        }
        return text
            .font(LookFont.text(13.5))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("today-journal-line")
    }

    private func insightsRow(_ doc: PFTodayJournal530?) -> some View {
        NavigationLink(value: TabRoute.plan529(.journalInsights)) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Behaviour insights")
                        .font(LookFont.text(14, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    if let sub = PFTodayJournalLogic530.insightsLine(doc) {
                        Text(sub)
                            .font(LookFont.text(12.5))
                            .foregroundStyle(NoopLook.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-journal-insights")
    }

    // MARK: The phone's own journal

    private func loadOwnDays() async {
        let monday = PFFormat.monday(of: today)
        var days = await repo.nativeJournalDays(from: monday, to: PFFormat.addDays(monday, 6))
        #if DEBUG
        // UI tests: the demo data logs every day up to yesterday; this switch (the old card's) takes yesterday out.
        if ProcessInfo.processInfo.arguments.contains("-JournalYesterdayUnlogged") { days.remove(PFFormat.addDays(today, -1)) }
        #endif
        ownDays = days
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE"
        return f
    }()

    private static func weekdayName(_ iso: String) -> String { weekdayFormatter.string(from: PFFormat.date(iso)) }
}
