import SwiftUI
import StrandDesign

// Personal behaviour experiments, under the journal's behaviour insights: one habit question, one outcome read the next morning, one dated
// window (`experiment` job: define, review, retire; the list is `GET data/experiments.json`). The reading is computed by the server on every
// review and is an association between two groups of days. Its caveat is shown with it, word for word, and no number is shown while a side
// has too few days. The inputs and how a review reads are in PaceForgeSourcedCharts.swift (unit-tested).

struct PFExperimentsCard530: View {
    /// The journal's active questions (the habit of an experiment is one of them).
    let questions: [String]

    @State private var list: [PFExperiment] = []
    @State private var state = PFDocPlaceholder529.Kind.loading
    @State private var defining = false
    @State private var reviewing: PFExperiment?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFOver529(text: "Your experiments")
            Text("Pick a habit and a reading and look at the mornings after yes and no days, for a window of dates you choose. It shows what lined up, not what caused it.")
                .font(LookFont.text(13))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            switch state {
            case .loading:
                ProgressView()
            case .failed:
                Text("PaceForge could not be reached, so your experiments are not on this phone yet.")
                    .font(LookFont.text(13.5)).foregroundStyle(NoopLook.textSecondary)
            case .empty:
                if list.isEmpty {
                    Text("No experiment yet.").font(LookFont.text(13.5)).foregroundStyle(NoopLook.textSecondary)
                }
            }
            ForEach(list) { experiment in row(experiment) }
            Button {
                defining = true
            } label: {
                Text("Start an experiment")
                    .font(LookFont.text(14, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(questions.isEmpty)
            .accessibilityIdentifier("pf530-experiment-define")
            if questions.isEmpty {
                PFWeekSub529(text: "An experiment is about one of your journal questions. Add a question first.")
            }
        }
        .planCard529()
        .containerIdentifier("pf530-experiments")
        .task { await load() }
        .sheet(isPresented: $defining) {
            PFExperimentDefineSheet530(questions: questions) { await load() }
        }
        .sheet(item: $reviewing) { experiment in
            PFExperimentReviewSheet530(experiment: experiment) { await load() }
        }
    }

    private func row(_ experiment: PFExperiment) -> some View {
        Button {
            reviewing = experiment
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(experiment.title)
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("\(experiment.question) \u{00B7} \(PFChartMetric.title(for: experiment.outcome)) \u{00B7} \(experiment.windowLine)")
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pf530-experiment-\(experiment.id)")
    }

    @MainActor private func load() async {
        guard PFAPI.isConfigured else {
            state = .empty
            return
        }
        let fetched = await PFAPI.fetchDoc("data/experiments.json")
        guard let data = fetched.data else {
            // Not served yet reads as no experiment; a server that could not be asked keeps what is shown.
            if fetched.failed { if list.isEmpty { state = .failed } } else { list = []; state = .empty }
            return
        }
        list = PFExperiment.parseList(data)
        state = .empty
    }
}

// MARK: Define

struct PFExperimentDefineSheet530: View {
    let questions: [String]
    let saved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = PFJobTracker()
    @State private var title = ""
    @State private var question: String?
    @State private var outcome = PFChartMetric.noopRecovery.rawValue
    @State private var start = PFAPI.todayISO
    @State private var end = PFFormat.addDays(PFAPI.todayISO, 13)
    @State private var message: String?

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    private var problem: String? {
        PFExperimentRules.problem(title: title, question: question, outcome: outcome, start: start, end: end, today: PFAPI.todayISO)
    }

    private func dateBinding(_ day: Binding<String>) -> Binding<Date> {
        Binding(get: { PFFormat.date(day.wrappedValue) }, set: { day.wrappedValue = PFFormat.isoString($0) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("Name") {
                        TextField("For example: caffeine and next-morning HRV", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("pf530-experiment-title")
                    }
                    field("Habit (one of your journal questions)") {
                        Picker("Habit", selection: $question) {
                            Text("Choose").tag(String?.none)
                            ForEach(questions, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("pf530-experiment-question")
                    }
                    field("Reading to compare the next morning") {
                        Picker("Reading", selection: $outcome) {
                            ForEach(PFChartMetric.allCases) { Text($0.title).tag($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("pf530-experiment-outcome")
                    }
                    field("From") {
                        DatePicker("From", selection: dateBinding($start), displayedComponents: .date).labelsHidden()
                    }
                    field("To (\(PFExperimentRules.minWindow) to \(PFExperimentRules.maxWindow) days in all)") {
                        DatePicker("To", selection: dateBinding($end), displayedComponents: .date).labelsHidden()
                    }
                    if let problem {
                        PFWeekSub529(text: problem)
                    }
                    if let message { Text(message).font(LookFont.text(13)).foregroundStyle(PFColor.warning) }
                    Button {
                        Task { await save() }
                    } label: {
                        Text(isBusy ? "Saving" : "Start experiment")
                            .font(LookFont.text(15, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .disabled(problem != nil || isBusy)
                    .accessibilityIdentifier("pf530-experiment-save")
                    PFWeekSub529(text: "Nothing is claimed below 5 days on each side, and nothing is called a difference below 10.")
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .lookScreenBackground()
            .navigationTitle("New experiment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            PFWeekOverline529(text: label)
            content()
        }
    }

    @MainActor private func save() async {
        guard let question,
              let inputs = PFJobInputs.experimentDefine(title: title, question: question, outcome: outcome, start: start, end: end,
                                                         today: PFAPI.todayISO) else { return }
        message = nil
        switch await tracker.run(.experiment, inputs: inputs) {
        case .failure(let failure):
            message = failure.message
        case .success:
            await saved()
            dismiss()
        }
    }
}

// MARK: Review

struct PFExperimentReviewSheet530: View {
    let experiment: PFExperiment
    let changed: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coach: AICoachEngine
    @EnvironmentObject private var router: NavRouter
    @StateObject private var tracker = PFJobTracker()
    @State private var review: PFExperimentReview?
    @State private var message: String?
    @State private var confirmsRetire = false

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let review {
                        content(review)
                    } else if isBusy {
                        HStack(spacing: 8) { ProgressView(); Text("Reading your mornings").font(LookFont.text(14)).foregroundStyle(NoopLook.textSecondary) }
                    }
                    if let message {
                        Text(message).font(LookFont.text(13.5)).foregroundStyle(PFColor.warning).fixedSize(horizontal: false, vertical: true)
                        Button("Try again") { Task { await load() } }.font(LookFont.text(14, weight: .semibold))
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle(experiment.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
            .confirmationDialog("Stop this experiment?", isPresented: $confirmsRetire, titleVisibility: .visible) {
                Button("Stop experiment", role: .destructive) { Task { await retire() } }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("It leaves your list. Your journal answers and readings are not touched.")
            }
        }
        .task { await load() }
    }

    @ViewBuilder private func content(_ review: PFExperimentReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: review.statusTitle)
            Text(review.statement)
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(review.countsLine).font(LookFont.text(13.5)).foregroundStyle(NoopLook.textSecondary)
            ForEach(review.effectLines(valueText: { valueText($0, review) }), id: \.self) { line in
                Text(line).font(LookFont.text(13.5)).foregroundStyle(NoopLook.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            if let gap = review.gapLine { PFWeekSub529(text: gap) }
        }
        .planCard529()
        .accessibilityIdentifier("pf530-experiment-review")
        VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: "What this is, and is not")
            Text(review.caveat)
                .font(LookFont.text(13.5))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pf530-experiment-caveat")
        }
        .planCard529()
        VStack(alignment: .leading, spacing: 6) {
            PFOver529(text: "The question")
            Text(questionSentence(review))
                .font(LookFont.text(13.5)).foregroundStyle(NoopLook.textSecondary).fixedSize(horizontal: false, vertical: true)
            PFWeekSub529(text: windowText(review))
        }
        .planCard529()
        Button {
            ask(review)
        } label: {
            Label("Ask the Coach about this experiment", systemImage: "bubble.left.and.bubble.right")
                .font(LookFont.text(14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf530-experiment-ask")
        Button(role: .destructive) {
            confirmsRetire = true
        } label: {
            Text("Stop this experiment").font(LookFont.text(14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(isBusy)
        .accessibilityIdentifier("pf530-experiment-retire")
    }

    private func valueText(_ value: Double, _ review: PFExperimentReview) -> String {
        let number = PFFormat.trimmed((value * 10).rounded() / 10)
        return review.outcomeUnit.isEmpty ? number : (review.outcomeUnit == "%" ? "\(number)%" : "\(number) \(review.outcomeUnit)")
    }

    private func questionSentence(_ review: PFExperimentReview) -> String {
        let source = review.outcomeSource.isEmpty ? "" : " (\(review.outcomeSource))"
        return "When you answered \u{201C}\(review.question)\u{201D} yes or no, the next morning's \(review.outcomeLabel)\(source)."
    }

    private func windowText(_ review: PFExperimentReview) -> String {
        var text = "Window \(PFFormat.shortDate(review.start)) to \(PFFormat.shortDate(review.end))"
        if let through = review.evaluatedThrough { text += ", read through \(PFFormat.shortDate(through))" }
        return text + ". Each yes or no is matched with the next morning."
    }

    /// The scoped Coach conversation about this experiment: `experiment:<id>` goes as the chat's session id and the Coach opens on Ask.
    private func ask(_ review: PFExperimentReview) {
        coach.pendingSessionID = review.scope
        coach.pendingPrompt = "What do you read from this experiment, and what would you try next?"
        UserDefaults.standard.set("ask", forKey: "noop.coach.chip")
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.openCoach() }
    }

    @MainActor private func load() async {
        guard let inputs = PFJobInputs.experimentAction("review", id: experiment.id) else { return }
        message = nil
        switch await tracker.run(.experiment, inputs: inputs) {
        case .failure(let failure):
            message = failure.message
        case .success(let result):
            if let parsed = PFExperimentReview.parse(result) {
                review = parsed
            } else {
                message = PFJobError.unreadable.message
            }
        }
    }

    @MainActor private func retire() async {
        guard let inputs = PFJobInputs.experimentAction("retire", id: experiment.id) else { return }
        switch await tracker.run(.experiment, inputs: inputs) {
        case .failure(let failure):
            message = failure.message
        case .success:
            await changed()
            dismiss()
        }
    }
}
