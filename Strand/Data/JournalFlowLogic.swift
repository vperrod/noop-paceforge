import Foundation

// MARK: - Journal flow (the staged answers behind SAVE JOURNAL)
//
// The journal screen in the look stages a day's answers on the screen and writes them when the user taps SAVE JOURNAL,
// instead of writing on every tap. Storage is unchanged: the same native answers (yes / no, or a number) under the same
// question keys, so the diff here is the minimal set of writes that turns what is saved into what is staged. Foundation only
// and pure, so it is unit tested.

enum JournalWrite: Equatable {
    case saveAnswer(question: String, yes: Bool)
    case clearAnswer(question: String)
    case saveNumber(question: String, value: Double)
    case clearNumber(question: String)
}

enum JournalFlowLogic {

    /// The writes that turn `saved` into `staged`, answers first and then numbers, each in question order.
    static func writes(savedAnswers: [String: Bool], stagedAnswers: [String: Bool],
                       savedNumbers: [String: Double], stagedNumbers: [String: Double]) -> [JournalWrite] {
        var out: [JournalWrite] = []
        for q in Set(savedAnswers.keys).union(stagedAnswers.keys).sorted() {
            switch (savedAnswers[q], stagedAnswers[q]) {
            case (let a?, let b?) where a != b: out.append(.saveAnswer(question: q, yes: b))
            case (nil, let b?): out.append(.saveAnswer(question: q, yes: b))
            case (_?, nil): out.append(.clearAnswer(question: q))
            default: break
            }
        }
        for q in Set(savedNumbers.keys).union(stagedNumbers.keys).sorted() {
            switch (savedNumbers[q], stagedNumbers[q]) {
            case (let a?, let b?) where a != b: out.append(.saveNumber(question: q, value: b))
            case (nil, let b?): out.append(.saveNumber(question: q, value: b))
            case (_?, nil): out.append(.clearNumber(question: q))
            default: break
            }
        }
        return out
    }

    /// A yes/no chip tapped: tapping the chip that is already chosen clears the answer (the card's tri-state rule).
    static func toggled(_ answers: [String: Bool], question: String, to value: Bool) -> [String: Bool] {
        var out = answers
        if out[question] == value { out.removeValue(forKey: question) } else { out[question] = value }
        return out
    }

    /// One day in the 7-day strip.
    struct StripDay: Equatable {
        /// 0 is today, 1 is yesterday, up to 6.
        var offset: Int
        var dayKey: String
        var weekday: String
        var dayOfMonth: Int
        var isLogged: Bool
        var isSelected: Bool
    }

    /// The seven days ending today, oldest first, each marked logged when `logged` holds its day key. `keyFor` turns an offset
    /// (days back) into the repository's local day key, and `partsFor` into its weekday letters and day of the month.
    static func strip(selectedOffset: Int, logged: Set<String>,
                      keyFor: (Int) -> String, partsFor: (Int) -> (weekday: String, day: Int)) -> [StripDay] {
        (0...6).reversed().map { offset in
            let key = keyFor(offset)
            let parts = partsFor(offset)
            return StripDay(offset: offset, dayKey: key, weekday: parts.weekday, dayOfMonth: parts.day,
                            isLogged: logged.contains(key), isSelected: offset == selectedOffset)
        }
    }

    /// The title between the stepper arrows: TOMORROW, TODAY, YESTERDAY, then "3 DAYS AGO".
    static func title(forOffset offset: Int) -> String {
        switch offset {
        case ..<0: return "TOMORROW"
        case 0: return "TODAY"
        case 1: return "YESTERDAY"
        default: return "\(offset) DAYS AGO"
        }
    }

    /// The question above the answers: "What's happening today, April 15?", "What happened yesterday, April 14?".
    static func question(forOffset offset: Int, dateText: String) -> String {
        switch offset {
        case ..<0: return "What's happening tomorrow, \(dateText)?"
        case 0: return "What's happening today, \(dateText)?"
        case 1: return "What happened yesterday, \(dateText)?"
        default: return "What happened on \(dateText)?"
        }
    }

    /// The stepper's bounds: tomorrow (-1) to six days back, the same window the journal has always allowed.
    static let offsetRange: ClosedRange<Int> = -1...6

    static func stepped(_ offset: Int, by step: Int) -> Int {
        min(max(offset + step, offsetRange.lowerBound), offsetRange.upperBound)
    }
}
