import SwiftUI
import StrandDesign

// "Plan match" on a recording's results: which planned or booked session it counts as. The same choices and the same two writes
// (`match-edit` link and unlink) as the PaceForge web activity page.

struct PFMatchControl: View {
    let activity: PFActivity
    /// Every planned and booked session, rest days left out (`PFSnapshot.sessions`).
    let sessions: [PFWorkout]
    /// Called once the server has taken a change: the session now matched, nil after Unmatch.
    let onChange: (String?) -> Void

    @EnvironmentObject private var model: PFModel
    @StateObject private var runner = PFEditJobRunner()
    @State private var picked: String?
    @State private var isSaving = false
    @State private var note: String?

    private var match: PFWorkout? { sessions.first { $0.matchedActivityIds.contains(activity.id) } }

    /// Sessions within a week either side of the recording's day, oldest first, without the one it counts as now. One that has a
    /// recording is offered too: linking replaces it.
    private var others: [PFWorkout] {
        let day = String((activity.startTime ?? "").prefix(10))
        guard !day.isEmpty else { return [] }
        let range = PFFormat.addDays(day, -7)...PFFormat.addDays(day, 7)
        return sessions.filter { range.contains($0.date) && $0.id != match?.id }.sorted { $0.date < $1.date }
    }

    private var selectedID: String? { (others.first { $0.id == picked } ?? others.first)?.id }

    var body: some View {
        PFCard("Plan match", icon: "link") {
            VStack(alignment: .leading, spacing: 10) {
                if let match {
                    Text("Counted as \(match.name ?? "session") \u{00B7} \(match.date).")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("pf-match-current")
                    PFWeekButton529(title: "Unmatch", isDisabled: isSaving, identifier: "pf-match-unlink") { Task { await save(nil) } }
                    PFParagraph("Detaches it and stops the matcher re-linking it there.")
                }
                if let selectedID {
                    Text("Count this as").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    Picker("Count this as", selection: Binding(get: { selectedID }, set: { picked = $0 })) {
                        ForEach(others) { Text(label($0)).tag($0.id) }
                    }
                    .pickerStyle(.menu)
                    .disabled(isSaving)
                    .accessibilityIdentifier("pf-match-session")
                    PFWeekButton529(title: isSaving ? "Working" : "Link to this session", isProminent: true, isDisabled: isSaving,
                                    identifier: "pf-match-link") { Task { await save(selectedID) } }
                } else if match == nil {
                    PFParagraph("Not counted against the plan \u{2014} no session within a week of this date.")
                }
                if let note {
                    Text(note)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.accent)
                        .accessibilityIdentifier("pf-match-note")
                }
                PFEditJobMessage(runner: runner)
            }
        }
        .containerIdentifier("pf-match-card")
    }

    private func label(_ session: PFWorkout) -> String {
        let name = session.name ?? (session.kind ?? "").replacingOccurrences(of: "_", with: " ")
        return "\(session.date) \u{2014} \(name)" + (session.matchedActivityIds.isEmpty ? "" : " (has a recording)")
    }

    /// Links to `sessionID`, or unmatches when it is nil.
    @MainActor private func save(_ sessionID: String?) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        note = nil
        guard await runner.run(.matchEdit, inputs: PFJobInputs.matchEdit(activityID: activity.id, sessionID: sessionID)) != nil else { return }
        // A load already running may have read the plan before this write, so it is followed by one more.
        let wasLoading = model.isRefreshing
        await model.refresh()
        if wasLoading { await model.refresh() }
        picked = nil
        note = (sessionID == nil ? "Unmatched" : "Linked") + ". Plan updated."
        onChange(sessionID)
    }
}
