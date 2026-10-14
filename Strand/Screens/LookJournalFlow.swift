#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - The journal, in the look's flow
//
// The week strip with a check on every day that has answers, a ‹ TODAY › stepper, the question for the day, the yes / no
// questions in groups (a number question gets a stepper and a slider), and SAVE JOURNAL, which writes the staged answers and shows
// SAVED. The questions, the groups, the renames and the storage are the journal's own: answers go to the same native rows under
// the same keys (`Repository.saveJournalAnswer` / `saveJournalNumeric` / `clearJournalAnswer`), tapping the chosen chip again
// clears it, and the previous card with its rename / regroup / add controls is one tap away under the pencil.

struct LookJournalFlow: View {
    @EnvironmentObject private var repo: Repository
    @StateObject private var catalog = JournalCatalogStore()

    /// Distinct imported question strings, adopted into the catalog so logged answers and imported history group together.
    let importedQuestions: [String]
    /// -1 is tomorrow (log ahead), 0 today, 1 yesterday, up to 6.
    @Binding var dayOffset: Int
    /// The parent re-reads its own journal data after a write.
    let onChanged: () -> Void
    /// The question editor was closed. The question list is read once when this view is made, so the parent makes it again to pick
    /// up a rename, a regroup or a new question.
    let onEditorClosed: () -> Void

    @State private var savedAnswers: [String: Bool] = [:]
    @State private var savedNumbers: [String: Double] = [:]
    @State private var stagedAnswers: [String: Bool] = [:]
    @State private var stagedNumbers: [String: Double] = [:]
    @State private var loggedDays: Set<String> = []
    @State private var loadedDay: String?
    @State private var isSaving = false
    @State private var showSaved = false
    @State private var showEditor = false

    private var calendar: Calendar { Calendar.current }

    private func date(forOffset offset: Int) -> Date {
        calendar.date(byAdding: .day, value: -offset, to: Date()) ?? Date()
    }

    private var dayKey: String { Repository.localDayKey(date(forOffset: dayOffset)) }

    private var loadKey: String { "\(dayOffset)|\(repo.refreshSeq)|\(Repository.localDayKey(Date()))" }

    private var items: [JournalCatalogItem] {
        catalog.resolvedItems(imported: importedQuestions, includeHidden: false)
    }

    private func items(in group: JournalGroup) -> [JournalCatalogItem] {
        items.filter { $0.group == group }.sorted { ($0.sortIndex, $0.display) < ($1.sortIndex, $1.display) }
    }

    private var writes: [JournalWrite] {
        JournalFlowLogic.writes(savedAnswers: savedAnswers, stagedAnswers: stagedAnswers,
                                savedNumbers: savedNumbers, stagedNumbers: stagedNumbers)
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showSaved {
                savedState
            } else {
                titleRow
                stepper
                strip
                Text(JournalFlowLogic.question(forOffset: dayOffset, dateText: Self.longDate(date(forOffset: dayOffset), dayOffset: dayOffset)))
                    .font(LookFont.text(24, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("look-journal-question")
                ForEach(JournalGroup.displayOrder, id: \.self) { group in
                    groupBlock(group)
                }
                saveButton
                // What the answers add up to, once there are enough days: PaceForge's journal impact.
                NavigationLink { PFJournalImpactScreen() } label: {
                    InsightLink("See what helps and hurts")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("look-journal-impact-link")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.insightRadius, style: .continuous).fill(NoopLook.tile))
        .containerIdentifier("look-journal-flow")
        .task(id: loadKey) { await load() }
        .sheet(isPresented: $showEditor, onDismiss: onEditorClosed) { editorSheet }
    }

    // MARK: Header, stepper and strip

    private var titleRow: some View {
        HStack {
            Text("JOURNAL").lookCaps(14).foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 8)
            Button { showEditor = true } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit the journal questions")
            .accessibilityIdentifier("look-journal-edit")
        }
    }

    private var stepper: some View {
        HStack(spacing: 12) {
            stepButton("chevron.left", label: "Earlier day", step: 1)
            Text(JournalFlowLogic.title(forOffset: dayOffset))
                .lookCaps(13)
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("look-journal-day")
            stepButton("chevron.right", label: "Later day", step: -1)
        }
        .frame(maxWidth: .infinity)
    }

    private func stepButton(_ symbol: String, label: String, step: Int) -> some View {
        let next = JournalFlowLogic.stepped(dayOffset, by: step)
        let direction = step > 0 ? "earlier" : "later"
        return Button { dayOffset = next } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(next == dayOffset ? NoopLook.textMuted : NoopLook.textPrimary)
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(next == dayOffset)
        .accessibilityLabel(label)
        .accessibilityIdentifier("look-journal-\(direction)")
    }

    private static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    private static func longDate(_ date: Date, dayOffset: Int) -> String {
        let f = DateFormatter()
        f.locale = AppLanguage.activeLocale
        f.setLocalizedDateFormatFromTemplate(dayOffset >= 2 ? "EEEEMMMMd" : "MMMMd")
        return f.string(from: date)
    }

    private var strip: some View {
        let days = JournalFlowLogic.strip(
            selectedOffset: dayOffset, logged: loggedDays,
            keyFor: { Repository.localDayKey(date(forOffset: $0)) },
            partsFor: { (weekday: Self.weekday(date(forOffset: $0)), day: calendar.component(.day, from: date(forOffset: $0))) })
        return HStack(spacing: 0) {
            ForEach(days, id: \.offset) { day in
                Button { dayOffset = day.offset } label: {
                    VStack(spacing: 6) {
                        Text(day.weekday).font(LookFont.text(12.5, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
                        Text("\(day.dayOfMonth)").font(LookFont.numeral(16)).foregroundStyle(NoopLook.textPrimary)
                        ZStack {
                            Circle().fill(day.isLogged ? NoopLook.trendUp : Color.clear)
                            Circle().strokeBorder(day.isLogged ? Color.clear : NoopLook.textMuted, lineWidth: 1.4)
                            if day.isLogged {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color.black)
                            }
                        }
                        .frame(width: 20, height: 20)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(day.isSelected ? NoopLook.row : Color.clear))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(day.isSelected ? NoopLook.textPrimary.opacity(0.9) : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(day.weekday) \(day.dayOfMonth), \(day.isLogged ? "logged" : "not logged")")
                .accessibilityAddTraits(day.isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("look-journal-strip-\(day.offset)")
            }
        }
        .containerIdentifier("look-journal-strip")
    }

    // MARK: Groups and questions

    @ViewBuilder private func groupBlock(_ group: JournalGroup) -> some View {
        let groupItems = items(in: group)
        if !groupItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                PFRuleLabel(group.title.uppercased())
                ForEach(groupItems) { item in
                    if item.kind.isNumeric { numberRow(item) } else { yesNoRow(item) }
                }
            }
        }
    }

    private func yesNoRow(_ item: JournalCatalogItem) -> some View {
        let current = stagedAnswers[item.canonical]
        return HStack(spacing: 12) {
            Text(verbatim: item.display)
                .font(LookFont.text(16, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            answerButton("xmark", isOn: current == false, onColor: Color.white, glyph: Color.black, label: "No", item: item, value: false)
            answerButton("checkmark", isOn: current == true, onColor: Color(hex: "#4D9CFF"), glyph: Color.white, label: "Yes", item: item, value: true)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 60)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-journal-row-\(item.canonical)")
    }

    private func answerButton(_ symbol: String, isOn: Bool, onColor: Color, glyph: Color, label: String,
                              item: JournalCatalogItem, value: Bool) -> some View {
        Button {
            stagedAnswers = JournalFlowLogic.toggled(stagedAnswers, question: item.canonical, to: value)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(isOn ? glyph : NoopLook.textSecondary)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isOn ? onColor : NoopLook.track))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label), \(item.display)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("look-journal-\(label.lowercased())-\(item.canonical)")
    }

    /// A number question: the value with its unit, a stepper either side, and a slider underneath.
    private func numberRow(_ item: JournalCatalogItem) -> some View {
        let value = stagedNumbers[item.canonical]
        let top = max(10, ((value ?? 0) * 1.5).rounded(.up))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(verbatim: item.display)
                    .font(LookFont.text(16, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(value.map { $0 == $0.rounded() ? String(Int($0)) : String(format: "%.1f", $0) } ?? "\u{2013}")
                    .font(LookFont.numeral(20))
                    .foregroundStyle(NoopLook.textPrimary)
                if let unit = item.kind.unitLabel, !unit.isEmpty {
                    Text(verbatim: unit).font(LookFont.text(12.5, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
                }
            }
            HStack(spacing: 12) {
                stepperButton("minus", item: item, delta: -1, label: "Decrease")
                Slider(value: Binding(get: { value ?? 0 }, set: { stagedNumbers[item.canonical] = ($0 * 2).rounded() / 2 }),
                       in: 0...top)
                    .tint(Color(hex: "#4D9CFF"))
                    .accessibilityLabel("\(item.display) value")
                    .accessibilityIdentifier("look-journal-slider-\(item.canonical)")
                stepperButton("plus", item: item, delta: 1, label: "Increase")
                if value != nil {
                    Button { stagedNumbers.removeValue(forKey: item.canonical) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(NoopLook.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(item.display)")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.rowRadius, style: .continuous).fill(NoopLook.row))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("look-journal-row-\(item.canonical)")
    }

    private func stepperButton(_ symbol: String, item: JournalCatalogItem, delta: Double, label: String) -> some View {
        Button {
            stagedNumbers[item.canonical] = max(0, (stagedNumbers[item.canonical] ?? 0) + delta)
        } label: {
            Image(systemName: "\(symbol).circle")
                .font(.system(size: 22))
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) \(item.display)")
        .accessibilityIdentifier("look-journal-\(symbol)-\(item.canonical)")
    }

    // MARK: Save

    private var saveButton: some View {
        let changed = !writes.isEmpty
        return Button { Task { await save() } } label: {
            Text("SAVE JOURNAL")
                .lookCaps(14)
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(changed ? 1 : 0.35)))
        }
        .buttonStyle(.plain)
        .disabled(!changed || isSaving)
        .accessibilityHint(changed ? "Saves your answers" : "Nothing new to save")
        .accessibilityIdentifier("look-journal-save")
    }

    private var savedState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().strokeBorder(Color(hex: "#19EC9A"), lineWidth: 5)
                Image(systemName: "checkmark").font(.system(size: 34, weight: .bold)).foregroundStyle(Color(hex: "#19EC9A"))
            }
            .frame(width: 96, height: 96)
            Text("SAVED").lookCaps(15).foregroundStyle(NoopLook.textPrimary)
            Text("Have a great day!").font(LookFont.text(15, weight: .medium)).foregroundStyle(NoopLook.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("look-journal-saved")
    }

    @MainActor private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let day = dayKey
        for write in writes {
            switch write {
            case .saveAnswer(let question, let yes): await repo.saveJournalAnswer(day: day, question: question, answeredYes: yes)
            case .saveNumber(let question, let value): await repo.saveJournalNumeric(day: day, question: question, value: value)
            case .clearAnswer(let question), .clearNumber(let question): await repo.clearJournalAnswer(day: day, question: question)
            }
        }
        onChanged()
        await load()
        withAnimation(.easeOut(duration: 0.2)) { showSaved = true }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        withAnimation(.easeOut(duration: 0.2)) { showSaved = false }
    }

    // MARK: Data

    @MainActor private func load() async {
        let day = dayKey
        let answers = await repo.nativeJournalAnswers(day: day)
        let numbers = await repo.nativeJournalNumeric(day: day)
        let from = Repository.localDayKey(date(forOffset: 6))
        let to = Repository.localDayKey(date(forOffset: 0))
        let logged = await repo.nativeJournalDays(from: from, to: to)
        guard !Task.isCancelled else { return }
        // A refresh that lands while the user is part-way through a day must not wipe what they have staged: only a day that has
        // nothing staged (or a different day) takes the saved answers.
        let untouched = stagedAnswers == savedAnswers && stagedNumbers == savedNumbers
        let sameDay = loadedDay == day
        savedAnswers = answers
        savedNumbers = numbers
        if untouched || !sameDay {
            stagedAnswers = answers
            stagedNumbers = numbers
        }
        loggedDays = logged
        loadedDay = day
    }

    // MARK: Editing the questions

    /// The previous journal card, for renaming, regrouping, hiding and adding questions.
    private var editorSheet: some View {
        NavigationStack {
            ScrollView {
                JournalLogCard(importedQuestions: importedQuestions, answers: savedAnswers, numericAnswers: savedNumbers,
                               dayOffset: $dayOffset, onChanged: { onChanged(); Task { await load() } })
                    .padding(16)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Journal questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showEditor = false }
                }
            }
        }
    }
}
#endif
