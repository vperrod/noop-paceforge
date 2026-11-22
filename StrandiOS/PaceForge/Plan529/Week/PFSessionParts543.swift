import SwiftUI
import StrandDesign

// The blocks of the session screen (build 543, drawings 3.2 to 3.7): what to do as numbered pieces, what you did against what was asked, the
// assessment and the notes thread with its composer. Each takes what it shows; the screen (PFSessionSheet529) owns the data and the sending.

// MARK: What to do

/// One numbered piece: "1 Warm-up 2 km", its effort word, the band the Coach will judge it against and its text.
struct PFPieceRow543: View {
    let piece: PFPlanWeekDoc.Piece
    let number: Int

    private let hiding = PFHiding()

    private var effort: String? { PFSessionText543.effortWord(piece.effort) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(PFPlanFont543.text(17, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .frame(minWidth: 28, alignment: .leading)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let label = PFPlanRow543.clean(piece.label) {
                        Text(label)
                            .font(PFPlanFont543.text(17, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let effort { PFWrapPill543(text: effort, color: PFWeekColor529.effort(piece.effort?.lowercased())) }
                }
                if let band = PFPlanRow543.clean(piece.band) {
                    Text(hiding.text(band))
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let text = PFPlanRow543.clean(piece.text) {
                    Text(hiding.text(text))
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if piece.unknown == true {
                    Text("The description does not say enough to judge this piece.")
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan529-piece-\(number)")
    }
}

/// "What to do \u{00B7} about 54 min, estimated" and the pieces; a workout without pieces shows its text once.
struct PFWhatToDoCard543: View {
    let item: PFPlanWeekDoc.Item

    private let hiding = PFHiding()

    var body: some View {
        let pieces = PFSessionText543.pieces(item)
        let fallback = PFSessionText543.fallbackText(item)
        if !pieces.isEmpty || fallback != nil {
            VStack(alignment: .leading, spacing: 12) {
                PFWeekOverline529(text: PFSessionText543.whatToDoHeader(item))
                ForEach(Array(pieces.enumerated()), id: \.offset) { offset, piece in
                    if offset > 0 { PFDivider529() }
                    PFPieceRow543(piece: piece, number: piece.n ?? offset + 1)
                }
                if let fallback {
                    Text(hiding.text(fallback))
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-session-text")
                }
            }
            .pfWeekCard()
            .containerIdentifier("plan529-session-do")
        }
    }
}

// MARK: What you did

/// Drawing 3.6: each piece as it was asked, what the recording shows for it and the verdict as a word. Without execution data the finished
/// session says what was done in one line.
struct PFWhatYouDidCard543: View {
    let item: PFPlanWeekDoc.Item
    let execution: PFSessionExecution543?

    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFWeekOverline529(text: PFSessionText543.whatYouDid)
            if let execution, execution.isAvailable {
                ForEach(Array(execution.rows.enumerated()), id: \.offset) { offset, row in
                    if offset > 0 { PFDivider529() }
                    rowView(row)
                }
                if let what = execution.whatHappened {
                    Text(hiding.text(what))
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-session-happened")
                }
                if !execution.limits.isEmpty { limits(execution.limits) }
            } else {
                if let line = PFPlanRow543.clean(item.done?.line) {
                    Text(hiding.text(line))
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-done-\(item.sessionId ?? "")")
                }
                if let reason = PFPlanRow543.clean(execution?.reason) {
                    Text(reason)
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-session-did")
    }

    private func rowView(_ row: PFSessionExecution543.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.asked)
                .font(PFPlanFont543.text(16, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("You did: " + hiding.text(row.did))
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PFWrapPill543(text: row.verdict, color: verdictColor(row.verdict))
            if let why = row.why {
                Text(why)
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan529-did-row-\(row.index)")
    }

    private func verdictColor(_ verdict: String) -> Color {
        switch verdict {
        case "On target": return PFWeekColor529.teal
        case "Under", "Over": return PFWeekColor529.amber
        default: return NoopLook.textSecondary
        }
    }

    private func limits(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Limits")
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan529-session-limits")
    }
}

// MARK: Assessment

/// The Coach's verdict on a finished workout, what it means, the next step, the version, and "Reassessing\u{2026}" while a new one is written.
struct PFAssessmentCard543: View {
    let item: PFPlanWeekDoc.Item
    let thread: PFSessionThread543?
    let isReassessing: Bool
    let openResults: (() -> Void)?

    private let hiding = PFHiding()

    private var hasReview: Bool { item.review?.state == "ready" && PFPlanRow543.clean(item.review?.verdict) != nil }

    var body: some View {
        if hasReview || isReassessing || openResults != nil {
            VStack(alignment: .leading, spacing: 10) {
                PFWeekOverline529(text: PFSessionText543.assessment)
                if isReassessing {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        ProgressView().accessibilityHidden(true)
                        Text(PFSessionText543.reassessing + " I am re-reading the workout with your note.")
                            .font(PFPlanFont543.text(16, weight: .semibold))
                            .foregroundStyle(NoopLook.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plan529-session-reassessing")
                }
                if hasReview, let verdict = PFPlanRow543.clean(item.review?.verdict) {
                    labelled("Verdict", hiding.text(verdict), id: "plan529-review-\(item.sessionId ?? "")")
                    if let meaning = PFPlanRow543.clean(item.review?.meaning) { labelled("What it means", hiding.text(meaning), id: "plan529-review-meaning-\(item.sessionId ?? "")") }
                    if let next = PFPlanRow543.clean(item.after) { labelled("Next", hiding.text(next), id: "plan529-session-next") }
                }
                if let version = thread?.latestVersion {
                    Text(PFSessionThread543.versionLine(version))
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-session-version")
                }
                if let openResults {
                    PFPlanButton543(title: "Open the results", isProminent: true, identifier: "plan529-session-results", action: openResults)
                }
            }
            .pfWeekCard()
            .containerIdentifier("plan529-session-assessment")
        }
    }

    private func labelled(_ label: String, _ text: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
            Text(text)
                .font(PFPlanFont543.text(16, weight: .regular))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }
}

// MARK: Notes

/// Drawing 3.7: the athlete's notes and the Coach's replies in one thread, the versions of the assessment and the composer.
struct PFNotesCard543: View {
    let thread: PFSessionThread543?
    /// Notes sent from this phone before the server's thread shows them.
    let localNotes: [String]
    @Binding var draft: String
    let isSending: Bool
    let status: String?
    let sendTitle: String
    let canSend: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFWeekOverline529(text: PFSessionText543.notes)
            ForEach(Array((thread?.messages ?? []).enumerated()), id: \.offset) { _, message in messageRow(message) }
            ForEach(Array(localNotes.enumerated()), id: \.offset) { _, text in
                messageRow(PFSessionThread543.Message(at: nil, from: "you", text: text))
            }
            versions
            TextField(PFSessionText543.composerPlaceholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...8)
                .font(PFPlanFont543.text(16, weight: .regular))
                .foregroundStyle(NoopLook.textPrimary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NoopLook.divider, lineWidth: 1))
                .focused(isFocused)
                .accessibilityLabel("Note for the Coach")
                .accessibilityIdentifier("plan529-session-note-input")
            PFPlanButton543(title: isSending ? "Sending\u{2026}" : sendTitle, isProminent: true, isDisabled: !canSend || isSending,
                            identifier: "plan529-session-note-send", action: onSend)
            if let status {
                Text(status)
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-session-note-status")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-session-notes")
    }

    private func messageRow(_ message: PFSessionThread543.Message) -> some View {
        let speaker = PFSessionThread543.speaker(message.from)
        return VStack(alignment: .leading, spacing: 2) {
            Text(speaker + (PFFormat.timeOfDay(message.at).map { " \u{00B7} \($0)" } ?? ""))
                .font(PFPlanFont543.text(15, weight: .semibold))
                .foregroundStyle(speaker == "Coach" ? PFColor.violet : NoopLook.textSecondary)
            Text(message.text)
                .font(PFPlanFont543.text(16, weight: .regular))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var versions: some View {
        let list = (thread?.versions ?? []).sorted { $0.number > $1.number }
        if list.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, version in
                    Text(PFSessionThread543.versionLine(version))
                        .font(PFPlanFont543.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(PFSessionText543.versionsHint)
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("plan529-session-versions")
        }
    }
}
