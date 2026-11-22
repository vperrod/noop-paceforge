import SwiftUI
import StrandDesign

// The small pieces the journal sheets share: the card of behaviours the devices answered, the evening card (from data/today-cards.json),
// and the questions the athlete added on the phone.

// MARK: - Answered by your devices (5b)

/// The behaviours a day's devices answered, each with its evidence. A tap corrects one: the phone's own answer replaces it, a second tap
/// takes the correction away. The "No" answers sit in one line under the card, with a way to open them as rows.
struct PFJournalAutoCard530: View {
    let rows: [PFJournalLogic530.AutoRow]
    let onTap: (PFJournalLogic530.AutoRow) -> Void
    @State private var showsNo = false

    var body: some View {
        let yes = rows.filter(\.yes)
        let no = rows.filter { !$0.yes }
        VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "Answered by your devices")
                .padding(.bottom, 4)
            ForEach(Array(yes.enumerated()), id: \.element.id) { index, row in
                if index > 0 { PFDivider529() }
                line(row)
            }
            if showsNo {
                ForEach(no, id: \.id) { row in
                    PFDivider529()
                    line(row)
                }
            }
            if !no.isEmpty || !yes.isEmpty {
                PFDivider529()
                Text(summary(no: no))
                    .font(PFPlanFont543.text(12.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .accessibilityIdentifier("pf530-journal-auto-note")
                if !no.isEmpty {
                    Button { showsNo.toggle() } label: {
                        Text(showsNo ? "Hide the No answers" : "Show the No answers")
                            .font(PFPlanFont543.text(13, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf530-journal-auto-toggle")
                }
            }
        }
        .planCard529()
        .containerIdentifier("pf530-journal-auto")
    }

    private func summary(no: [PFJournalLogic530.AutoRow]) -> String {
        guard !no.isEmpty else { return "Tap any row to correct it." }
        return no.map(\.label).joined(separator: ", ") + ": No. Tap any row to correct it."
    }

    private func line(_ row: PFJournalLogic530.AutoRow) -> some View {
        Button { onTap(row) } label: {
            PFRow529(title: row.label, sub: sub(row),
                     trailingPill: PFPill529(text: row.yes ? "Yes" : "No", tone: row.isCorrected ? .amber : (row.yes ? .teal : .grey)))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Tap to correct this answer")
        .accessibilityIdentifier("pf530-journal-auto-row-\(row.id)")
    }

    private func sub(_ row: PFJournalLogic530.AutoRow) -> String {
        guard row.isCorrected else { return row.evidence }
        return row.evidence.isEmpty ? "You changed this" : "\(row.evidence) · you changed this"
    }
}

// MARK: - The evening card (5d)

/// The `evening` block of data/today-cards.json, read here on its own so that a change to the Today overview's model never reaches the
/// journal. Every field is optional.
struct PFJournalEveningDoc530: Codable, Equatable {
    var evening: Evening?

    struct Evening: Codable, Equatable {
        var title: String?
        var verdict: String?
        var moved: String?
        var found: [String]?
        var tonight: String?
    }

    private enum CodingKeys: String, CodingKey { case evening }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        evening = try? container.decodeIfPresent(Evening.self, forKey: .evening)
    }

    init(evening: Evening? = nil) { self.evening = evening }
}

/// The day against the plan, what moved, and what the devices already put in the journal.
struct PFJournalEveningCard530: View {
    let heading: String
    let evening: PFJournalEveningDoc530.Evening?
    /// The behaviours the devices answered yes to today, when the evening card names none.
    let foundFallback: [String]
    private let hiding = PFHiding()

    var body: some View {
        let found = (evening?.found?.isEmpty == false) ? (evening?.found ?? []) : foundFallback
        VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: evening?.title ?? heading)
            if let verdict = evening?.verdict, !verdict.isEmpty {
                Text(hiding.text(verdict))
                    .font(PFPlanFont543.text(19, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf530-journal-verdict")
            }
            if let moved = evening?.moved, !moved.isEmpty {
                block("What moved today") {
                    Text(hiding.text(moved))
                        .font(PFPlanFont543.text(13.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !found.isEmpty {
                block("Already in your journal") {
                    LookFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(found, id: \.self) { PFPill529(text: $0, tone: .grey) }
                    }
                }
            }
        }
        .planCard529()
        .containerIdentifier("pf530-journal-evening-card")
    }

    private func block<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PFPlanFont543.text(13.5, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            content()
        }
    }
}

// MARK: - Questions added on the phone

/// The questions the athlete added in Customise, kept on the phone. Each one's text is its key.
enum PFJournalCustom530 {
    private static let storageKey = "pf530.journal.custom"
    private static let dismissedKey = "pf530.journal.suggestions.dismissed"

    static func load() -> [PFJournalLogic530.Custom] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([PFJournalLogic530.Custom].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [PFJournalLogic530.Custom]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: storageKey) }
    }

    static func questions() -> [PFJournalDoc530.Question] {
        load().map(\.question)
    }

    /// The suggestions the athlete answered (Keep, Not now, or acted on), as "action|key|title".
    static func dismissed() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    static func dismiss(_ id: String) {
        var all = dismissed()
        all.insert(id)
        UserDefaults.standard.set(Array(all).sorted(), forKey: dismissedKey)
    }

    static func suggestionID(_ suggestion: PFJournalDoc530.Suggestion) -> String {
        "\(suggestion.action ?? "")|\(suggestion.key ?? "")|\(suggestion.title ?? "")"
    }
}
