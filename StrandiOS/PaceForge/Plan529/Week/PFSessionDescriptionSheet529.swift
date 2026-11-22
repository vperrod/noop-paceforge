import SwiftUI
import UIKit
import StrandDesign

// The athlete's hand on the words of a workout: "Edit description" on the session sheet and on every week card, for a planned, a done and a coach's
// session. The text starts as the FULL current text (line breaks kept), the name can change too, and Save sends `calendar-edit` (description / name);
// on a done workout "Save and reassess" also asks the Coach to read it again. What is typed stays on the phone until the server takes it.
// The inputs, limits and result are in PaceForgeSessionDescription.swift (unit-tested).

/// A multi-line field of a fixed, large height that scrolls inside (the text of a workout runs long), with a placeholder and a character count.
struct PFLargeTextField529: View {
    let placeholder: String
    @Binding var text: String
    let limit: Int
    var height: CGFloat = 260
    let identifier: String

    private var count: Int { PFSessionDescription.length(text) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(LookFont.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textPrimary)
                    .padding(8)
                    .frame(height: height)
                    .accessibilityIdentifier(identifier)
                if text.isEmpty {
                    Text(placeholder)
                        .font(LookFont.text(15, weight: .regular))
                        .foregroundStyle(NoopLook.textTertiary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NoopLook.divider, lineWidth: 1))
            Text("\(count) / \(limit)")
                .font(LookFont.text(11, weight: .regular))
                .foregroundStyle(count > limit ? PFWeekColor529.amber : NoopLook.textTertiary)
                .accessibilityIdentifier("\(identifier)-count")
        }
    }
}

/// What the edit sheet is opened for: one session, its present text and name, and what the sheet must know to offer the right buttons.
struct PFDescribeTarget529: Equatable {
    let sessionID: String
    let title: String
    let description: String
    let isDone: Bool
    let isCoach: Bool
    let isEdited: Bool

    init(item: PFPlanWeekDoc.Item, sessionID: String) {
        self.sessionID = sessionID
        title = item.title ?? ""
        description = PFSessionDescription.currentText(description: item.description, coachDetails: item.coachDetails, do: item.do)
        isDone = ["done", "partial"].contains(item.status ?? "")
        isCoach = item.coachAssigned == true
        isEdited = item.athleteEdited == true
    }
}

/// "Edit description" and the sentence under it after a save. Its own host view for the sheet: stacked presentation modifiers on one view can
/// leave only the last one working.
struct PFEditDescriptionButton529: View {
    let target: PFDescribeTarget529
    let idPrefix: String

    @State private var isOpen = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                PFWeekButton529(title: "Edit description", identifier: "\(idPrefix)-describe") { isOpen = true }
                if target.isCoach, target.isEdited, note == nil {
                    Text(PFSessionDescription.editedLine)
                        .font(LookFont.text(12, weight: .regular))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityIdentifier("\(idPrefix)-describe-edited")
                }
            }
            if let note {
                Text(note)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("\(idPrefix)-describe-result")
            }
        }
        .sheet(isPresented: $isOpen) {
            PFSessionDescriptionSheet529(target: target) { sentNote in
                note = sentNote
                UIAccessibility.post(notification: .announcement, argument: sentNote)
            }
        }
    }
}

/// The edit sheet: a name field, the description in a large field prefilled with the full current text, Save (and Save and reassess on a done
/// workout), and for a coach's session Restore coach text (asks first) with a small "Edited by you" line.
struct PFSessionDescriptionSheet529: View {
    let target: PFDescribeTarget529
    let onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var draft: PFSessionDescriptionDraft
    @State private var asksToRestore = false

    init(target: PFDescribeTarget529, onSaved: @escaping (String) -> Void) {
        self.target = target
        self.onSaved = onSaved
        let key = PFSessionDescription.draftKey(sessionID: target.sessionID)
        _draft = State(initialValue: PFSessionDescriptionKeeping.opening(kept: UserDefaults.standard.data(forKey: key),
                                                                         sessionID: target.sessionID,
                                                                         description: target.description, name: target.title))
    }

    private var key: String { PFSessionDescription.draftKey(sessionID: target.sessionID) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PFWeekSub529(text: intro)
                    VStack(alignment: .leading, spacing: 6) {
                        PFWeekOverline529(text: "Name")
                        TextField("Name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("plan529-describe-name")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        PFWeekOverline529(text: "Description")
                        PFLargeTextField529(placeholder: PFSessionDescription.addHint, text: $draft.description,
                                            limit: PFSessionDescription.maxLength, height: 300,
                                            identifier: "plan529-describe-text")
                    }
                    if target.isCoach, target.isEdited { editedRow }
                    if let problem = draft.hasChanges ? draft.problem : nil { PFWeekSub529(text: problem) }
                    PFEditMessage529(runner: runner)
                    buttons
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
            .lookScreenBackground()
            .navigationTitle("Edit description")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("plan529-describe-cancel")
                }
            }
        }
        .containerIdentifier("plan529-describe")
        // What is typed stays on the phone until the server takes it, even when the sheet is swiped away.
        .onChange(of: draft) { _, now in
            if let data = PFSessionDescriptionKeeping.toStore(now) {
                UserDefaults.standard.set(data, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        .confirmationDialog(PFSessionDescription.restoreQuestion, isPresented: $asksToRestore, titleVisibility: .visible) {
            Button(PFSessionDescription.restoreConfirmTitle, role: .destructive) { Task { await restore() } }
        }
    }

    private var intro: String {
        if target.isDone { return "\(target.title). Add what you did and how it felt, or correct the text. Save and reassess asks the Coach to read the workout again with it." }
        return "\(target.title). Change the text as you like, add details or comments. Only what you change is sent."
    }

    private var editedRow: some View {
        Text(PFSessionDescription.editedLine)
            .font(LookFont.text(12, weight: .regular))
            .foregroundStyle(NoopLook.textTertiary)
            .accessibilityIdentifier("plan529-describe-edited")
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 8) {
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                PFWeekButton529(title: runner.isBusy ? "Saving" : "Save", isProminent: !target.isDone,
                                isDisabled: runner.isBusy || !draft.canSend, identifier: "plan529-describe-save") {
                    Task { await save(reassess: false) }
                }
                if target.isDone {
                    PFWeekButton529(title: runner.isBusy ? "Saving" : "Save and reassess", isProminent: true,
                                    isDisabled: runner.isBusy || !draft.canSend, identifier: "plan529-describe-save-reassess") {
                        Task { await save(reassess: true) }
                    }
                }
                if PFSessionDescription.canRestoreCoachText(isCoachAssigned: target.isCoach) {
                    PFWeekButton529(title: PFSessionDescription.restoreTitle, isDisabled: runner.isBusy,
                                    identifier: "plan529-describe-restore") { asksToRestore = true }
                }
                if draft.hasChanges {
                    PFWeekButton529(title: "Start over", isDisabled: runner.isBusy, identifier: "plan529-describe-reset") {
                        draft = draft.startedOver()
                        runner.clear()
                    }
                }
            }
        }
    }

    // MARK: Jobs

    @MainActor private func save(reassess: Bool) async {
        let flag = PFSessionDescription.reassessFlag(isDone: target.isDone, wantsReassess: reassess)
        let took = await runner.run(.calendarEdit, inputs: draft.inputs(reassess: flag))
        // A send the server refused leaves the sheet open with everything typed; the text is already kept on the phone by `onChange`.
        guard took else { return }
        UserDefaults.standard.removeObject(forKey: key)
        let note = PFSessionDescriptionResult(runner.lastResult).note(reassessAsked: flag == true)
        await finish(note)
    }

    @MainActor private func restore() async {
        guard await runner.run(.calendarEdit, inputs: PFJobInputs.calendarRestoreCoachText(sessionID: target.sessionID)) else { return }
        UserDefaults.standard.removeObject(forKey: key)
        await finish(PFSessionDescription.restoredNote)
    }

    @MainActor private func finish(_ note: String) async {
        await PFUnified.model.refresh()
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        onSaved(note)
        dismiss()
    }
}
