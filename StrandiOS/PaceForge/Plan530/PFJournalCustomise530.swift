import SwiftUI
import StrandDesign

/// The journal's question editor (screen 5f): the list with when each question is asked and its yes and no count, the coach's suggestions
/// (the card is absent while the server sends none), and "Add your own" with its question, kind and time of day. Renaming, regrouping and
/// hiding stay in the journal's own editor, one tap away. A question added here is kept on the phone and asked in the window chosen.
struct PFJournalCustomise530: View {
    typealias Logic = PFJournalLogic530

    @StateObject private var store = PFDocStore529<PFJournalDoc530>(path: PFDocPath529.journal)
    @State private var customs = PFJournalCustom530.load()
    @State private var dismissed = PFJournalCustom530.dismissed()
    @State private var hidden: Set<String> = []
    @State private var draft = ""
    @State private var draftKind = "yes_no"
    @State private var draftWindow = Logic.evening
    @State private var showsEditor = false

    private struct KindOption: Identifiable {
        let id: String
        let title: String
    }

    private static let kinds = [
        KindOption(id: "yes_no", title: "Yes or no"), KindOption(id: "count", title: "How many"),
        KindOption(id: "time", title: "A time"), KindOption(id: "scale", title: "1 to 5"),
    ]

    var body: some View {
        content
            .planScreen529(title: "Customise journal", identifier: "pf530-journal-customise")
            .task { await store.refresh() }
            .onAppear { hidden = Set(JournalCatalogStore().hiddenQuestions) }
            .reloadsAfterPull529 { await store.refresh() }
            .sheet(isPresented: $showsEditor, onDismiss: { hidden = Set(JournalCatalogStore().hiddenQuestions) }) { editorSheet }
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
            VStack(alignment: .leading, spacing: 12) {
                if store.isStale { PFStaleNote529() }
                listCard(doc)
                suggestionsCard(doc)
                addCard(doc)
                editorRow
            }
        }
    }

    // MARK: The list

    private func listCard(_ doc: PFJournalDoc530) -> some View {
        let questions = (doc.list ?? []).filter { !($0.key ?? "").isEmpty }
        let visible = questions.filter { !hidden.contains($0.key ?? "") }.count + customs.count
        return VStack(alignment: .leading, spacing: 0) {
            PFOver529(text: "Your list · \(visible) of \(Logic.maxQuestions)")
                .padding(.bottom, 4)
                .accessibilityIdentifier("pf530-journal-list-count")
            ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                if index > 0 { PFDivider529() }
                let key = question.key ?? ""
                PFRow529(title: question.label ?? Logic.prompt(question), sub: asked(question), trailing: counts(question),
                         trailingPill: hidden.contains(key) ? PFPill529(text: "Hidden", tone: .grey) : nil)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("pf530-journal-list-row-\(key)")
            }
            ForEach(customs, id: \.key) { custom in
                PFDivider529()
                HStack(spacing: 8) {
                    PFRow529(title: custom.key, sub: "\(when(window: custom.window, about: nil)) · added by you")
                    Button { remove(custom) } label: {
                        Text("Remove")
                            .font(LookFont.text(13, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf530-journal-custom-remove-\(custom.key)")
                }
                .containerIdentifier("pf530-journal-custom-row-\(custom.key)")
            }
        }
        .planCard529()
        .containerIdentifier("pf530-journal-list")
    }

    private func asked(_ question: PFJournalDoc530.Question) -> String {
        let time = when(window: question.window, about: question.about)
        let prompt = Logic.prompt(question)
        return prompt.isEmpty ? time : "\(prompt) · \(time)"
    }

    private func when(window: String?, about: String?) -> String {
        let name: String
        switch window ?? Logic.evening {
        case Logic.morning: name = "Morning"
        case Logic.afternoon: name = "Afternoon"
        default: name = "Evening"
        }
        return about == "yesterday" ? "\(name), about yesterday" : name
    }

    private func counts(_ question: PFJournalDoc530.Question) -> String {
        "\(question.nYes ?? 0) yes · \(question.nNo ?? 0) no"
    }

    // MARK: The coach suggests

    @ViewBuilder private func suggestionsCard(_ doc: PFJournalDoc530) -> some View {
        let open = (doc.suggestions ?? []).filter { !dismissed.contains(PFJournalCustom530.suggestionID($0)) && !($0.title ?? "").isEmpty }
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PFOver529(text: "The coach suggests")
                ForEach(Array(open.enumerated()), id: \.offset) { _, suggestion in
                    let id = PFJournalCustom530.suggestionID(suggestion)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(suggestion.title ?? "")
                            .font(LookFont.text(14.5, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let reason = suggestion.reason, !reason.isEmpty {
                            Text(PFHiding().text(reason))
                                .font(LookFont.text(12.5))
                                .foregroundStyle(NoopLook.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 8) {
                            PFPillButton529(title: actionTitle(suggestion), isMain: true) { act(on: suggestion, id: id) }
                                .accessibilityIdentifier("pf530-journal-suggestion-go-\(id)")
                            PFPillButton529(title: suggestion.action == "add" ? "Not now" : "Keep") { dismiss(id) }
                                .accessibilityIdentifier("pf530-journal-suggestion-skip-\(id)")
                        }
                    }
                    .containerIdentifier("pf530-journal-suggestion-\(id)")
                }
            }
            .planCard529()
            .containerIdentifier("pf530-journal-suggestions")
        }
    }

    private func actionTitle(_ suggestion: PFJournalDoc530.Suggestion) -> String {
        switch suggestion.action ?? "" {
        case "drop": return "Drop"
        case "add": return "Add"
        default: return "Change"
        }
    }

    /// Drop hides the question in the journal's catalog; add asks the new question in the evening; change does both.
    private func act(on suggestion: PFJournalDoc530.Suggestion, id: String) {
        let catalog = JournalCatalogStore()
        if suggestion.action != "add", let key = suggestion.key, !key.isEmpty { catalog.remove(key) }
        if suggestion.action != "drop", let title = suggestion.title { add(title, kind: "yes_no", window: Logic.evening, existing: existingKeys(nil)) }
        hidden = Set(catalog.hiddenQuestions)
        dismiss(id)
    }

    private func dismiss(_ id: String) {
        PFJournalCustom530.dismiss(id)
        dismissed = PFJournalCustom530.dismissed()
    }

    // MARK: Add your own

    private func addCard(_ doc: PFJournalDoc530) -> some View {
        let existing = existingKeys(doc)
        let visible = (doc.list ?? []).filter { !hidden.contains($0.key ?? "") }.count
        let fits = Logic.canAdd(listCount: visible, customCount: customs.count)
        let key = Logic.newKey(draft, existing: existing)
        return VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "Add your own")
            TextField("Describe it: \"Did you have a late work call?\"", text: $draft, axis: .vertical)
                .font(LookFont.text(15))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(NoopLook.row))
                .accessibilityIdentifier("pf530-journal-add-text")
            HStack(spacing: 12) {
                Text("Answer")
                    .font(LookFont.text(13.5, weight: .medium))
                    .foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Picker("Answer", selection: $draftKind) {
                    ForEach(Self.kinds) { Text($0.title).tag($0.id) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pf530-journal-add-kind")
            }
            SectionChips(options: Logic.windows, selection: $draftWindow, idPrefix: "pf530-journal-add-window",
                         id: { $0 }, title: { $0.capitalized })
            if !fits {
                Text("The list holds \(Logic.maxQuestions) questions. Hide one in the editor below to make room.")
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf530-journal-add-full")
            }
            PFPillButton529(title: "Add question", isMain: true, isDisabled: key == nil || !fits) {
                if let key { add(key, kind: draftKind, window: draftWindow, existing: existing) }
            }
            .accessibilityIdentifier("pf530-journal-add")
            Text("It is asked in the window you pick and saved under your own words.")
                .font(LookFont.text(12.5))
                .foregroundStyle(NoopLook.textTertiary)
        }
        .planCard529()
        .containerIdentifier("pf530-journal-add-card")
    }

    private func existingKeys(_ doc: PFJournalDoc530?) -> [String] {
        let fromDoc = (doc ?? store.doc)?.list?.compactMap(\.key) ?? []
        return fromDoc + customs.map(\.key)
    }

    /// Keeps the question on the phone and in the journal's catalog (a number question there when it asks for more than yes or no).
    private func add(_ text: String, kind: String, window: String, existing: [String]) {
        guard let key = Logic.newKey(text, existing: existing) else { return }
        customs.append(Logic.Custom(key: key, kind: kind, window: window))
        PFJournalCustom530.save(customs)
        JournalCatalogStore().addCustom(key, kind: kind == "yes_no" ? .bool : .numeric(unitLabel: nil))
        draft = ""
    }

    private func remove(_ custom: Logic.Custom) {
        customs.removeAll { $0.key == custom.key }
        PFJournalCustom530.save(customs)
        JournalCatalogStore().remove(custom.key)
    }

    // MARK: The journal's own editor

    private var editorRow: some View {
        Button { showsEditor = true } label: {
            PFRow529(title: "Rename, regroup or hide questions", sub: "The journal's editor", showsChevron: true)
                .planCard529(padding: 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf530-journal-editor")
    }

    private var editorSheet: some View {
        PFJournalEditorSheet530()
    }
}

/// The earlier journal editor (rename, regroup, hide, convert) in a sheet of its own.
private struct PFJournalEditorSheet530: View {
    @EnvironmentObject private var repo: Repository
    @Environment(\.dismiss) private var dismiss
    @State private var dayOffset = 0
    @State private var answers: [String: Bool] = [:]
    @State private var numbers: [String: Double] = [:]

    var body: some View {
        NavigationStack {
            ScrollView {
                JournalLogCard(importedQuestions: [], answers: answers, numericAnswers: numbers, dayOffset: $dayOffset,
                               onChanged: { Task { await load() } })
                    .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Journal questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("pf530-journal-editor-done")
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        let day = Repository.localDayKey(Date())
        answers = await repo.nativeJournalAnswers(day: day)
        numbers = await repo.nativeJournalNumeric(day: day)
    }
}
