import SwiftUI

/// A written or spoken journal entry proposes answers. The athlete chooses which answers to save.
/// Voice is the same route as typing: the phone transcribes on the device (`CoachVoiceInput`, no audio leaves it), the transcript lands in the
/// box below where it can be corrected, and it goes to `journal-capture` as `text`. Only `journal-capture-confirm`, after the review, saves.
struct PFJournalTextCapture530: View {
    let day: String
    let questions: [String]
    let saved: () async -> Void

    @StateObject private var job = PFJobTracker()
    @StateObject private var voice = CoachVoiceInput()
    /// What was in the box when the dictation began; the transcript goes after it.
    @State private var textBeforeVoice = ""
    @State private var text = ""
    @State private var draft: Draft?
    @State private var selected: Set<String> = []
    @State private var message: String?
    @State private var busy = false

    private struct Draft: Decodable {
        let id: String
        let day: String
        let answers: [Answer]
        let unanswered: [String]
    }

    private struct Answer: Decodable, Identifiable {
        let day: String
        let question: String
        let answer: String
        let number: Double?
        let evidence: String
        var id: String { question }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write your day").font(.headline)
            Text("Write or say what happened. Review any proposed answers before saving them.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 92)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.3)))
                .accessibilityLabel("Journal text")
            if CoachVoiceInput.isSupported {
                Button { toggleVoice() } label: {
                    Label(voice.isRecording ? "Stop" : "Speak", systemImage: voice.isRecording ? "stop.circle.fill" : "mic.fill")
                }
                .disabled(busy || !(voice.isRecording || voice.canUseVoice || voice.authorization == .notDetermined))
                .accessibilityIdentifier("pf530-journal-voice")
                if let status = voice.statusMessage { Text(status).font(.caption).foregroundStyle(.secondary) }
            }
            Button("Review answers") { Task { await review() } }
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || questions.isEmpty)
            if let draft {
                Text("\(draft.day) · \(draft.answers.count) proposed · \(draft.unanswered.count) unanswered")
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(draft.answers) { row in
                    Toggle(isOn: Binding(get: { selected.contains(row.question) },
                                         set: { on in
                                             if on { selected.insert(row.question) }
                                             else { selected.remove(row.question) }
                                         })) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(row.day) · \(row.question): \(row.answer)\(row.number.map { " · \($0)" } ?? "")")
                            Text("“\(row.evidence)”").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !draft.answers.isEmpty {
                    Button("Save selected answers") { Task { await confirm() } }
                        .disabled(busy || selected.isEmpty)
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .planCard529()
        .onDisappear { if voice.isRecording { voice.stopTranscribing { _ in } } }
    }

    /// Dictation fills the box live; stopping keeps the final transcript. Nothing is sent until "Review answers".
    private func toggleVoice() {
        if voice.isRecording {
            voice.stopTranscribing { finalText in
                let spoken = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !spoken.isEmpty { text = joined(textBeforeVoice, spoken) }
            }
            return
        }
        textBeforeVoice = text
        let begin = {
            voice.startTranscribing { partial in text = joined(textBeforeVoice, partial) }
        }
        if voice.authorization == .notDetermined {
            voice.requestAuthorization { state in if state == .authorized { begin() } }
        } else {
            begin()
        }
    }

    /// The box's text then the transcript, within the 2 000 characters `journal-capture` takes.
    private func joined(_ before: String, _ spoken: String) -> String {
        let parts = [before.trimmingCharacters(in: .whitespacesAndNewlines), spoken.trimmingCharacters(in: .whitespacesAndNewlines)]
        return String(parts.filter { !$0.isEmpty }.joined(separator: " ").prefix(2000))
    }

    @MainActor private func review() async {
        busy = true
        defer { busy = false }
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        let inputs: [String: Any] = ["draft_id": id, "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                                     "day": day, "questions": Array(questions.prefix(10))]
        guard case .success = await job.run(.journalCapture, inputs: inputs) else {
            message = "Could not prepare a review. Your text is still here."
            return
        }
        do {
            let data = try await PFAPI.fetch("journal-capture/\(id)")
            let result = try JSONDecoder().decode(Draft.self, from: data)
            draft = result
            selected = Set(result.answers.map(\.question))
            message = result.answers.isEmpty ? "No explicit answers found. Add detail or answer the questions directly." : nil
        } catch {
            message = "Could not read the review. Your text is still here."
        }
    }

    @MainActor private func confirm() async {
        guard let draft else { return }
        busy = true
        defer { busy = false }
        let answers: [[String: Any]] = draft.answers.filter { selected.contains($0.question) }.map { row in
            var item: [String: Any] = ["question": row.question, "answer": row.answer]
            if let number = row.number { item["number"] = number }
            return item
        }
        guard case .success = await job.run(.journalCaptureConfirm,
                                            inputs: ["draft_id": draft.id, "answers": answers]) else {
            message = "Save did not complete. Your text and review are still here."
            return
        }
        self.draft = nil
        text = ""
        selected = []
        message = "Answers saved."
        await saved()
    }
}
