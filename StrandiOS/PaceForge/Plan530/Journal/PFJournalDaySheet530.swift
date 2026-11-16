import SwiftUI
import StrandDesign

/// The morning sheet (5b) and the evening reflection (5d): one screen per window of the day. The morning one is about last night: what the
/// devices answered, then the questions only the night can answer, pre-filled from the day before. The evening one is about today: the
/// evening card, then the day's questions. Answers are saved to the day the behaviour happened (`PFJournalLogic530.behaviourDay`),
/// through the journal's own store; Save, Done and leaving the screen all write what is on it.
struct PFJournalDaySheet530: View {
    typealias Logic = PFJournalLogic530

    let window: String

    @EnvironmentObject private var repo: Repository
    @StateObject private var store = PFDocStore529<PFJournalDoc530>(path: PFDocPath529.journal)
    @StateObject private var cards = PFDocStore529<PFJournalEveningDoc530>(path: PFDocPath529.todayCards)
    @StateObject private var session = PFJournalSession530()

    private var isMorning: Bool { window == Logic.morning }
    private var today: String { PFAPI.todayISO }
    private var identifier: String { "pf530-journal-\(window)" }

    private var title: String {
        guard isMorning else { return "Evening reflection" }
        let day = Logic.behaviourDay(about: nil, window: window, today: today)
        return "About \(Logic.dayName(day) ?? "yesterday")"
    }

    var body: some View {
        content
            .planScreen529(title: title, identifier: identifier)
            .task {
                await store.refresh()
                if !isMorning { await cards.refresh() }
            }
            .reloadsAfterPull529 { await store.refresh() }
    }

    @ViewBuilder private var content: some View {
        switch store.state {
        case .loading:
            PFDocPlaceholder529(kind: .loading)
        case .empty:
            PFDocPlaceholder529(kind: .empty, emptyTitle: "No questions yet",
                                emptyText: "PaceForge has not published your journal questions. They show here once it has.")
        case .failed:
            PFDocPlaceholder529(kind: .failed, failedText: "PaceForge could not be reached, so the journal questions are not on this phone yet.",
                                retry: { Task { await store.refresh() } })
        case .loaded(let doc):
            loaded(doc)
        }
    }

    // MARK: The loaded sheet

    @ViewBuilder private func loaded(_ doc: PFJournalDoc530) -> some View {
        let hidden = Set(JournalCatalogStore().hiddenQuestions)
        let questions = Logic.questions(in: doc.list, window: window, hidden: hidden, extra: PFJournalCustom530.questions())
        let keys = questions.compactMap(\.key)
        let day = Logic.day(window: window, questions: questions, today: today)
        let autoIDs = (doc.auto ?? []).first { $0.date == day }?.answers?.compactMap(\.id) ?? []
        VStack(alignment: .leading, spacing: 12) {
            if store.isStale { PFStaleNote529() }
            if isMorning {
                autoCard(doc, day: day, keys: keys, autoIDs: autoIDs)
            } else {
                eveningCard(doc)
            }
            if questions.isEmpty {
                PFDocPlaceholder529(kind: .empty, emptyTitle: "Nothing to answer",
                                    emptyText: isMorning ? "No question is asked in the morning." : "No question is asked in the evening.")
            } else {
                questionsCard(questions, keys: keys, day: day)
                saveBar(keys: keys, day: day)
            }
            if !isMorning { tonightCard }
        }
        .task(id: "\(day)|\(keys.joined(separator: "|"))") {
            await session.load(repo: repo, day: day, keys: keys, readsPrevious: isMorning)
        }
        .onDisappear {
            let writes = session.pending(keys: keys, allowsPrevious: isMorning)
            if !writes.isEmpty { Task { await session.commit(repo: repo, day: day, keys: keys, allowsPrevious: isMorning) } }
        }
    }

    // MARK: Cards

    @ViewBuilder private func autoCard(_ doc: PFJournalDoc530, day: String, keys: [String], autoIDs: [String]) -> some View {
        let rows = Logic.autoRows(doc, date: day, corrections: session.corrections(ids: autoIDs))
        if !rows.isEmpty {
            PFJournalAutoCard530(rows: rows) { row in
                Task { await session.correct(row, repo: repo, day: day, keys: keys, readsPrevious: isMorning) }
            }
        }
    }

    @ViewBuilder private func eveningCard(_ doc: PFJournalDoc530) -> some View {
        let evening = cards.doc?.evening
        let found = ((doc.auto ?? []).first { $0.date == today }?.answers ?? [])
            .filter { $0.answer == true }.compactMap(\.label)
        if evening != nil || !found.isEmpty {
            PFJournalEveningCard530(heading: Logic.dayName(today) ?? "Today", evening: evening, foundFallback: found)
        }
    }

    @ViewBuilder private var tonightCard: some View {
        if let tonight = cards.doc?.evening?.tonight, !tonight.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                PFOver529(text: "Tonight")
                Text(PFHiding().text(tonight))
                    .font(LookFont.text(14.5))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .planCard529()
            .containerIdentifier("pf530-journal-tonight")
        }
    }

    private func questionsCard(_ questions: [PFJournalDoc530.Question], keys: [String], day: String) -> some View {
        let staged = session.staged(keys: keys, allowsPrevious: isMorning)
        let taps = questions.count == 1 ? "1 tap" : "\(questions.count) taps"
        return VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: isMorning ? "For you · \(taps)" : "Today · \(taps)")
                .padding(.bottom, 4)
            if isMorning { sameAsYesterday }
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                if index > 0 || isMorning { PFDivider529() }
                PFJournalQuestionRow530(
                    question: question,
                    answer: staged[question.key ?? ""],
                    onChoose: { yes in
                        session.choose(key: question.key ?? "", kind: Logic.kind(question), yes: yes, keys: keys, allowsPrevious: isMorning)
                    },
                    onNumber: { session.setNumber(key: question.key ?? "", $0, keys: keys, allowsPrevious: isMorning) },
                    onNote: { session.setNote(key: question.key ?? "", $0, keys: keys, allowsPrevious: isMorning) })
            }
        }
        .planCard529()
        .containerIdentifier("pf530-journal-questions")
    }

    private var sameAsYesterday: some View {
        Toggle(isOn: $session.usePrevious) {
            Text("Same as yesterday")
                .font(LookFont.text(14, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
        }
        .tint(StrandPalette.accent)
        .frame(minHeight: 44)
        .accessibilityIdentifier("pf530-journal-same")
    }

    // MARK: Save

    private func saveBar(keys: [String], day: String) -> some View {
        let answered = Logic.answeredCount(keys: keys, saved: session.saved)
        let pending = session.pending(keys: keys, allowsPrevious: isMorning)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("\(answered) of \(keys.count) answered")
                    .font(LookFont.text(13, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                    .accessibilityIdentifier("pf530-journal-answered")
                Spacer(minLength: 8)
                if session.didSave && pending.isEmpty {
                    Text("Saved")
                        .lookCaps(11, weight: .semibold)
                        .foregroundStyle(NoopLook.trendUp)
                        .accessibilityIdentifier("pf530-journal-saved")
                }
            }
            if !pending.isEmpty {
                PFPillButton529(title: "Save answers", isMain: true, isDisabled: session.isSaving) {
                    Task { await session.commit(repo: repo, day: day, keys: keys, allowsPrevious: isMorning) }
                }
                .accessibilityIdentifier("pf530-journal-save")
            }
        }
    }
}
