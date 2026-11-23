import SwiftUI
import StrandDesign

// The Coach's questions about a finished workout, one screen at a time (build 543, drawings 3.4 and 3.5). The model of the flow, the typed
// answers and the payload are in PFWorkoutQuestions543.swift (unit-tested); this file only draws them and sends the answer through the
// existing Needs you door (`POST app/answer`, kinds `workout_answer` / `workout_answer_skip`).

struct PFWorkoutQuestionFlow543: View {
    let item: PFNeedsItem

    @ObservedObject private var model = PFUnified.model
    @State private var flow: PFQuestionFlow543
    @State private var isSending = false

    init(item: PFNeedsItem) {
        self.item = item
        let ask = item.workout ?? PFWorkoutAsk543(activityID: item.activityID ?? "", name: item.title, date: nil, round: 0, questions: [])
        _flow = State(initialValue: PFQuestionFlow543(ask: ask))
    }

    private var idSuffix: String { item.activityID ?? item.id }
    private var totalSeconds: Double? { model.snapshot?.activities[item.activityID ?? ""]?.durationS }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            Text(titleLine)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let page = flow.currentPage {
                pageView(page)
                if let blocker = flow.blocker(page), pageHasInput(page) {
                    Text(blocker)
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(PFWeekColor529.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-q-blocker-\(idSuffix)")
                }
                buttons(page)
            } else {
                Text("Nothing is left to ask.")
                    .font(PFPlanFont543.text(16, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
            }
            if let note = model.needsNotes[item.id] {
                Label(note, systemImage: "exclamationmark.circle")
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-q-error-\(idSuffix)")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-questions-\(idSuffix)")
    }

    // MARK: Header

    private var titleLine: String {
        let name = PFPlanRow543.clean(flow.ask.name) ?? PFPlanRow543.clean(item.title) ?? "your workout"
        guard let date = flow.ask.date, PFJobInputs.isDay(date) else { return name }
        return date == PFAPI.todayISO ? "\(name), done today" : "\(name), \(PFFormat.dayTitle(date))"
    }

    private var topRow: some View {
        HStack(alignment: .center) {
            if flow.canGoBack {
                Button { flow.back() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("plan529-q-back-\(idSuffix)")
            }
            Spacer(minLength: 4)
            Text(flow.positionLine)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
                .accessibilityLabel("Question \(flow.positionLine)")
                .accessibilityIdentifier("plan529-q-position-\(idSuffix)")
        }
    }

    // MARK: Pages

    @ViewBuilder private func pageView(_ page: PFQuestionPage543) -> some View {
        switch page.style {
        case .exact:
            ForEach(page.questions) { question in exactQuestion(question) }
        case .segments:
            segmentsPage(page)
        case .piece:
            ForEach(page.questions) { question in pieceQuestion(question) }
        }
    }

    private func pageHasInput(_ page: PFQuestionPage543) -> Bool {
        page.questions.contains { flow.typed[$0.key] != nil || flow.chosen[$0.key] != nil } || page.style == .exact
    }

    /// Drawing 3.4: "Did you do it exactly as written?" with the written workout under it and three answers.
    private func exactQuestion(_ question: PFWorkoutQuestion543) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.text)
                .font(PFPlanFont543.text(22, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let written = writtenLine { Text(written).questionSub() }
            choiceChips(question, includesUnknown: false)
            Text("Yes skips most other questions. If it was mostly or not at all as written, say what changed in a note on the session.")
                .questionSub()
        }
    }

    /// The workout as the session describes it, in one line, when the week page already holds it.
    private var writtenLine: String? {
        guard let id = item.activityID else { return nil }
        let line = model.snapshot?.weeks.flatMap { $0.days }.flatMap { $0.workouts }.first { $0.activityId == id }?.name
        return PFPlanRow543.clean(line)
    }

    /// Drawing 3.5: where the piece ran, as a bar and three answers.
    private func segmentsPage(_ page: PFQuestionPage543) -> some View {
        let confirm = page.questions.first { $0.key == PFQuestionFlow543.segmentsKey }
        return VStack(alignment: .leading, spacing: 12) {
            if let confirm {
                Text(confirm.text)
                    .font(PFPlanFont543.text(22, weight: .bold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let start = confirm.proposedStartS, let end = confirm.proposedEndS,
                   let shares = PFPieceTimeline543.shares(startS: start, endS: end, totalS: totalSeconds) {
                    PFPieceTimelineBar543(shares: shares, startS: start, endS: end, totalS: totalSeconds)
                }
                if let why = confirm.why { Text(why).questionSub() }
                LookFlowLayout(spacing: 8, lineSpacing: 8) {
                    PFPlanChoiceChip543(title: "Looks right", isSelected: flow.chosen[confirm.key] == "yes",
                                        identifier: "plan529-q-seg-yes-\(idSuffix)") { flow.choose(confirm.key, "yes") }
                    PFPlanChoiceChip543(title: "Adjust", isSelected: flow.chosen[confirm.key] == "adjust",
                                        identifier: "plan529-q-seg-adjust-\(idSuffix)") { flow.choose(confirm.key, "adjust") }
                    PFPlanChoiceChip543(title: "I did it differently", isSelected: flow.unknown.contains(confirm.key),
                                        identifier: "plan529-q-seg-differently-\(idSuffix)") { flow.markUnknown(confirm.key) }
                }
            }
            ForEach(page.questions.filter { $0.key != PFQuestionFlow543.segmentsKey }) { question in numberField(question) }
        }
    }

    /// A piece or modality question: its words, why it is asked, and the answer it takes.
    private func pieceQuestion(_ question: PFWorkoutQuestion543) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.text)
                .font(PFPlanFont543.text(18, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let why = question.why { Text("Why I ask: " + why).questionSub() }
            switch question.kind {
            case .choice: choiceChips(question, includesUnknown: true)
            case .number, .date: input(question)
            }
        }
    }

    private func choiceChips(_ question: PFWorkoutQuestion543, includesUnknown: Bool) -> some View {
        LookFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(question.choices, id: \.self) { choice in
                PFPlanChoiceChip543(title: PFQuestionFlow543.choiceTitle(choice), isSelected: flow.chosen[question.key] == choice,
                                    identifier: "plan529-q-\(question.key)-\(choice)") { flow.choose(question.key, choice) }
            }
            if includesUnknown {
                PFPlanChoiceChip543(title: PFQuestionFlow543.unknownTitle, isSelected: flow.unknown.contains(question.key),
                                    identifier: "plan529-q-\(question.key)-unknown") { flow.markUnknown(question.key) }
            }
        }
    }

    private func numberField(_ question: PFWorkoutQuestion543) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question.text)
                .font(PFPlanFont543.text(16, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            input(question)
        }
    }

    /// A typed number (with its unit written out) or date, a note when it is the last similar workout's answer, and "I don't know".
    private func input(_ question: PFWorkoutQuestion543) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(PFQuestionFlow543.placeholder(question), text: Binding(
                get: { flow.typed[question.key] ?? "" },
                set: { flow.setText(question.key, $0) }))
                .textFieldStyle(.plain)
                .keyboardType(.numbersAndPunctuation)
                .font(PFPlanFont543.text(17, weight: .regular))
                .foregroundStyle(NoopLook.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NoopLook.divider, lineWidth: 1))
                .accessibilityLabel(question.text)
                .accessibilityIdentifier("plan529-q-input-\(question.key)")
            if let unit = PFQuestionFlow543.unitWords(question.unit), question.kind == .number {
                Text("In " + unit).questionSub()
            }
            if let parsed = flow.parsedSecondsLine(question) { Text(parsed).questionSub() }
            if question.confirmsPrefill, flow.typed[question.key] != nil, !flow.unknown.contains(question.key) {
                Text("From your last similar workout. Change it if it was different.").questionSub()
            }
            if let issue = flow.problem(question) {
                Text(issue)
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PFPlanChoiceChip543(title: PFQuestionFlow543.unknownTitle, isSelected: flow.unknown.contains(question.key),
                                identifier: "plan529-q-\(question.key)-unknown") { flow.markUnknown(question.key) }
        }
    }

    // MARK: Buttons

    private func buttons(_ page: PFQuestionPage543) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            PFPlanButton543(title: flow.isLastPage ? "Send answers" : "Next", isProminent: true,
                            isDisabled: isSending || flow.blocker(page) != nil,
                            identifier: "plan529-q-next-\(idSuffix)") {
                if flow.isLastPage { Task { await send(flow.finalAnswer) } } else { flow.next() }
            }
            Button {
                Task { await send(.workoutSkip(activityID: flow.ask.activityID)) }
            } label: {
                Text(PFQuestionFlow543.skipTitle)
                    .font(PFPlanFont543.text(16, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .underline()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSending)
            .accessibilityIdentifier("plan529-q-skip-\(idSuffix)")
        }
    }

    @MainActor private func send(_ answer: PFNeedsAnswer) async {
        guard !flow.ask.activityID.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        _ = await model.submitAnswer(answer, for: item)
    }
}

private extension Text {
    /// The small explanation under a question: still 15 points, in the secondary colour.
    func questionSub() -> some View {
        self.font(PFPlanFont543.text(15, weight: .regular))
            .foregroundStyle(NoopLook.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The bar of drawing 3.5: warm-up, the piece, cooldown, with the times written out beside it (the colours alone say nothing).
struct PFPieceTimelineBar543: View {
    let shares: PFPieceTimeline543.Shares
    let startS: Double
    let endS: Double
    let totalS: Double?

    private var legend: String {
        var line = "Before: 0:00 to \(PFPieceTimeline543.clock(startS)). The piece: \(PFPieceTimeline543.clock(startS)) to \(PFPieceTimeline543.clock(endS))."
        if let totalS, totalS > endS { line += " After: \(PFPieceTimeline543.clock(endS)) to \(PFPieceTimeline543.clock(totalS))." }
        return line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                HStack(spacing: 2) {
                    Rectangle().fill(PFWeekColor529.blue.opacity(0.55)).frame(width: max(0, width * shares.before))
                    Rectangle().fill(PFWeekColor529.teal).frame(width: max(4, width * shares.piece))
                    Rectangle().fill(PFWeekColor529.blue.opacity(0.55)).frame(width: max(0, width * shares.after))
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: 18)
            .accessibilityHidden(true)
            Text(legend)
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(legend)
        .accessibilityIdentifier("plan529-q-timeline")
    }
}

/// The question flow as its own screen, for the Needs you card on Today.
struct PFWorkoutQuestionSheet543: View {
    let item: PFNeedsItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PFWorkoutQuestionFlow543(item: item)
                    .padding(.horizontal, NoopLook.Metric.screenInset)
                    .padding(.top, 8)
                    .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .lookScreenBackground()
            .navigationTitle("Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(PFPlanFont543.text(16, weight: .semibold))
                        .accessibilityIdentifier("plan529-q-done")
                }
            }
        }
    }
}
