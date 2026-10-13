import SwiftUI
import StrandDesign

// "Add measurement": the sheet that logs a tape measurement or a field test from the iPhone. It sends the phrase
// to PaceForge (POST api/app/log), which reads it with the same code Telegram uses, so the formats are the same
// as typing to the bot. The sheet shows the server's own answer, a confirmation or the reason it said no.
// The pure half (phrase building, checks, how an answer reads) is in PaceForgeLog.swift and is unit-tested.

/// A button that opens the sheet on the tape or the field-test side. It needs the PaceForge model in the
/// environment, which every PaceForge screen has.
struct PFAddMeasurementButton: View {
    let kind: PFLogKind
    let title: String
    @EnvironmentObject private var model: PFModel
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Label(title, systemImage: "plus.circle")
                .font(StrandFont.subhead.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(StrandPalette.accent)
        .accessibilityIdentifier("pf-add-\(kind.rawValue)-button")
        .sheet(isPresented: $isShowing) { sheet }
    }

    /// The model is taken here and handed on as a plain function, so the sheet does not depend on the
    /// environment reaching it.
    private var sheet: some View {
        let sender = model
        return PFAddMeasurementSheet(initialKind: kind) { sentKind, phrase in
            await sender.submitLog(kind: sentKind, text: phrase)
        }
    }
}

struct PFAddMeasurementSheet: View {
    let submit: (PFLogKind, String) async -> PFLogOutcome
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PFLogKind
    @State private var tapeValues: [String: String] = [:]
    @State private var fieldTestText = ""
    @State private var isSaving = false
    @State private var outcome: PFLogOutcome?

    init(initialKind: PFLogKind, submit: @escaping (PFLogKind, String) async -> PFLogOutcome) {
        self.submit = submit
        _kind = State(initialValue: initialKind)
    }

    private var phrase: String {
        kind == .tape ? (PFLog.tapePhrase(tapeValues) ?? "") : PFLog.cleanedPhrase(fieldTestText)
    }

    private var problem: String? {
        if kind == .tape { return PFLog.tapeProblem(tapeValues) }
        let typed = PFLog.cleanedPhrase(fieldTestText)
        return typed.unicodeScalars.count > PFLog.maxChars ? "That is too long: keep it under \(PFLog.maxChars) characters." : nil
    }

    private var canSave: Bool { !isSaving && problem == nil && PFLog.canSend(phrase) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("What are you adding?", selection: kindBinding) {
                        ForEach(PFLogKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("pf-add-kind")
                    if kind == .tape { tapeCard } else { fieldTestCard }
                    saveButton
                    if let outcome { resultLine(outcome) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle("Add measurement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-add-done")
                }
            }
        }
        .presentationDetents([.large])
        .containerIdentifier("pf-add-sheet")
    }

    /// Switching sides drops the last answer: it was about the other side.
    private var kindBinding: Binding<PFLogKind> {
        Binding(get: { kind }, set: { kind = $0; outcome = nil })
    }

    private func tapeBinding(_ key: String) -> Binding<String> {
        Binding(get: { tapeValues[key] ?? "" }, set: { tapeValues[key] = $0 })
    }

    // MARK: Tape

    private var tapeCard: some View {
        PFCard("Tape measurements", icon: "ruler") {
            VStack(alignment: .leading, spacing: 10) {
                PFParagraph("In centimetres. Fill in what you measured today and leave the rest empty. A second entry on the same day fills in or replaces just the sites it names.")
                ForEach(PFLog.tapeSites, id: \.key) { site in
                    HStack(spacing: 12) {
                        Text(site.title)
                            .font(StrandFont.subhead.weight(.semibold))
                            .foregroundStyle(StrandPalette.textPrimary)
                        Spacer(minLength: 8)
                        TextField("cm", text: tapeBinding(site.key))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(site.title) in centimetres")
                            .accessibilityIdentifier("pf-add-tape-\(site.key)")
                    }
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(PFColor.warning)
                        .accessibilityIdentifier("pf-add-problem")
                }
            }
        }
    }

    // MARK: Field test

    private var fieldTestCard: some View {
        PFCard("Field test", icon: "figure.strengthtraining.traditional") {
            VStack(alignment: .leading, spacing: 12) {
                PFParagraph("Type the test and your number, the way you would to the Telegram bot. Lifts take the weight and the reps, like squat 140 x 5. Tap an example to start from it.")
                TextField("push-ups 35", text: $fieldTestText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pf-add-fieldtest-text")
                if let problem {
                    Label(problem, systemImage: "exclamationmark.circle")
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(PFColor.warning)
                        .accessibilityIdentifier("pf-add-problem")
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(PFLog.fieldTests, id: \.example) { test in
                        Button { fieldTestText = test.example } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(test.title)
                                    .font(StrandFont.subhead)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Spacer(minLength: 8)
                                Text(test.example)
                                    .font(StrandFont.caption.weight(.semibold))
                                    .foregroundStyle(StrandPalette.accent)
                            }
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(test.title), for example \(test.example)")
                        if test.example != PFLog.fieldTests.last?.example { Divider().overlay(StrandPalette.hairline) }
                    }
                }
            }
        }
    }

    // MARK: Save

    private var saveButton: some View {
        Button { save() } label: {
            HStack(spacing: 8) {
                if isSaving { ProgressView() }
                Text(isSaving ? "Saving" : "Save")
                    .font(StrandFont.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .tint(StrandPalette.accent)
        .disabled(!canSave)
        .accessibilityIdentifier("pf-add-save")
    }

    private func resultLine(_ outcome: PFLogOutcome) -> some View {
        Label(outcome.message, systemImage: outcome.isSaved ? "checkmark.circle" : "exclamationmark.circle")
            .font(StrandFont.subhead)
            .foregroundStyle(outcome.isSaved ? PFNeutral.main : PFColor.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(outcome.isSaved ? "pf-add-saved" : "pf-add-refused")
    }

    private func save() {
        guard canSave else { return }
        let text = phrase
        let sending = kind
        isSaving = true
        outcome = nil
        Task { @MainActor in
            let result = await submit(sending, text)
            isSaving = false
            outcome = result
            if result.isSaved {
                tapeValues = [:]
                fieldTestText = ""
            }
        }
    }
}
