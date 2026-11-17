import SwiftUI
import WhoopStore

/// The answers of one journal window on screen: what the journal saved for the day the behaviour happened, what "Same as yesterday" adds,
/// the athlete's edits, and the save. Every write goes through the journal's own store (`Repository.saveJournalAnswer`,
/// `saveJournalNumeric`, `clearJournalAnswer`), under the question's key exactly as the document names it. The decisions are in
/// `PFJournalLogic530`.
@MainActor
final class PFJournalSession530: ObservableObject {
    typealias Logic = PFJournalLogic530

    /// What the journal holds for the day, by question key (the questions and the device behaviours the athlete corrected).
    @Published private(set) var saved: [String: Logic.Answer] = [:]
    /// What the journal holds for the day before: the source of "Same as yesterday".
    @Published private(set) var previous: [String: Logic.Answer] = [:]
    @Published private(set) var edits: [String: Logic.Edit] = [:]
    @Published var usePrevious = true
    @Published private(set) var isSaving = false
    /// The last save wrote everything on screen; the next edit clears it.
    @Published private(set) var didSave = false
    @Published private(set) var saveFailed = false

    private var seededPrevious = false
    private var needsSave = false

    // MARK: On screen

    func staged(keys: [String], allowsPrevious: Bool) -> [String: Logic.Answer] {
        Logic.staged(saved: saved, previous: previous, usePrevious: allowsPrevious && usePrevious, keys: keys, edits: edits)
    }

    func pending(keys: [String], allowsPrevious: Bool) -> [Logic.Write] {
        Logic.writes(saved: saved, staged: staged(keys: keys, allowsPrevious: allowsPrevious), keys: keys)
    }

    /// The device behaviours the athlete corrected, by behaviour id.
    func corrections(ids: [String]) -> [String: Bool] {
        var out: [String: Bool] = [:]
        for id in ids { if let answer = saved[id] { out[id] = answer.yes } }
        return out
    }

    // MARK: Edits

    func choose(key: String, kind: String, yes: Bool, keys: [String], allowsPrevious: Bool) {
        let current = staged(keys: keys, allowsPrevious: allowsPrevious)[key]
        edits[key] = Logic.choose(kind: kind, yes: yes, current: current, defaultTime: Self.minutesNow())
        didSave = false
        saveFailed = false
    }

    func setNumber(key: String, _ number: Double?, keys: [String], allowsPrevious: Bool) {
        guard let current = staged(keys: keys, allowsPrevious: allowsPrevious)[key] else { return }
        edits[key] = .set(Logic.withNumber(current, number))
        didSave = false
        saveFailed = false
    }

    func setNote(key: String, _ note: String?, keys: [String], allowsPrevious: Bool) {
        guard let current = staged(keys: keys, allowsPrevious: allowsPrevious)[key] else { return }
        edits[key] = .set(Logic.withNote(current, note))
        didSave = false
        saveFailed = false
    }

    static func minutesNow() -> Double {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double((parts.hour ?? 12) * 60 + (parts.minute ?? 0))
    }

    // MARK: Journal store

    /// Reads the day (and, for a window that pre-fills, the day before) from the journal.
    func load(repo: Repository, day: String, keys: [String], readsPrevious: Bool) async {
        #if DEBUG
        await seedPreviousIfRequested(repo: repo, day: day, keys: keys, readsPrevious: readsPrevious)
        #endif
        let entries = await repo.journalEntries(days: 30)
        saved = await Self.answers(on: day, repo: repo, entries: entries)
        if readsPrevious, let before = Logic.addDays(day, -1) {
            previous = await Self.answers(on: before, repo: repo, entries: entries)
        }
    }

    private static func answers(on day: String, repo: Repository, entries: [JournalEntry]) async -> [String: Logic.Answer] {
        let yes = await repo.nativeJournalAnswers(day: day)
        let numbers = await repo.nativeJournalNumeric(day: day)
        var notes: [String: String] = [:]
        for entry in entries where entry.day == day {
            if let note = entry.notes, !note.isEmpty { notes[entry.question] = note }
        }
        var out: [String: Logic.Answer] = [:]
        for (question, answeredYes) in yes {
            out[question] = Logic.Answer(yes: answeredYes, number: answeredYes ? numbers[question] : nil, note: answeredYes ? notes[question] : nil)
        }
        return out
    }

    /// Offer a late Apple Health caffeine sample as a pre-filled positive answer. Save still requires a tap.
    /// Absence of a sample is not a "No": Health permission or import may be incomplete.
    func prefillCaffeineFromHealthKit(day: String, keys: [String]) {
        let key = "Did you have caffeine late in the day?"
        guard keys.contains(key), saved[key] == nil, edits[key] == nil else { return }
        let bedtime = UserDefaults.standard.object(forKey: CaffeineLogCard.bedtimeMinutesKey) as? Int ?? 23 * 60
        let late = CaffeineLogStore.shared.intakes.contains { intake in
            guard intake.isImported, PFFormat.isoString(intake.at) == day else { return false }
            let time = Calendar.current.dateComponents([.hour, .minute], from: intake.at)
            return CaffeineDecay.isPastCutoff(intakeMinutes: (time.hour ?? 0) * 60 + (time.minute ?? 0), bedtimeMinutes: bedtime)
        }
        guard late else { return }
        edits[key] = .set(Logic.Answer(yes: true, note: "Apple Health: past bedtime caffeine cutoff"))
    }

    /// Writes what is on screen that the journal does not hold yet, then reads the day again.
    func commit(repo: Repository, day: String, keys: [String], allowsPrevious: Bool) async {
        if isSaving {
            needsSave = true
            return
        }
        isSaving = true
        defer { isSaving = false }
        for _ in 0..<3 {
            needsSave = false
            let writes = pending(keys: keys, allowsPrevious: allowsPrevious)
            guard !writes.isEmpty else { break }
            let committedEdits = edits
            await Self.perform(writes, day: day, repo: repo)
            await load(repo: repo, day: day, keys: keys, readsPrevious: allowsPrevious)
            // Keep edits made during the write, and any write the store did not actually retain.
            edits = edits.filter { key, edit in
                guard committedEdits[key] == edit else { return true }
                if case .set(let answer) = edit { return saved[key] != answer }
                return true
            }
            if pending(keys: keys, allowsPrevious: allowsPrevious) == writes && !needsSave { break }
            if !needsSave && pending(keys: keys, allowsPrevious: allowsPrevious).isEmpty { break }
        }
        saveFailed = !pending(keys: keys, allowsPrevious: allowsPrevious).isEmpty
        didSave = !saveFailed && !saved.isEmpty
    }

    /// The athlete taps a device answer: the phone's own answer replaces it, or goes again when it was already there.
    func correct(_ row: Logic.AutoRow, repo: Repository, day: String, keys: [String], readsPrevious: Bool) async {
        await Self.perform([Logic.correction(for: row)], day: day, repo: repo)
        await load(repo: repo, day: day, keys: keys, readsPrevious: readsPrevious)
    }

    static func perform(_ writes: [Logic.Write], day: String, repo: Repository) async {
        for write in writes {
            switch write {
            case .clear(let question):
                await repo.clearJournalAnswer(day: day, question: question)
            case .save(let question, let answer):
                if answer.yes, let number = answer.number {
                    await repo.saveJournalNumeric(day: day, question: question, value: number, notes: answer.note)
                } else {
                    await repo.saveJournalAnswer(day: day, question: question, answeredYes: answer.yes, notes: answer.note)
                }
            }
        }
    }

    #if DEBUG
    /// UI tests: `-Journal530SeedPrevious` writes the day before's answers (the first question yes, the second no) so that "Same as
    /// yesterday" has something to pre-fill. The same journal store the screen reads.
    private func seedPreviousIfRequested(repo: Repository, day: String, keys: [String], readsPrevious: Bool) async {
        guard readsPrevious, !seededPrevious, ProcessInfo.processInfo.arguments.contains("-Journal530SeedPrevious"),
              let before = Logic.addDays(day, -1) else { return }
        seededPrevious = true
        if let first = keys.first { await repo.saveJournalAnswer(day: before, question: first, answeredYes: true) }
        if keys.count > 1 { await repo.saveJournalAnswer(day: before, question: keys[1], answeredYes: false) }
    }
    #endif
}
