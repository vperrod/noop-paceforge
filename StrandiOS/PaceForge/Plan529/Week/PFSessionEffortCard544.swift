import SwiftUI
import UIKit
import StrandDesign

// "How hard" on the session screen (build 544): the athlete has the last word on a session's effort and minutes, the coach's sessions included.
// Four choices, a minutes stepper, "Your choice" or "Estimated" beside each value, and "Reset to estimate" while a choice exists. Save sends
// `session-effort` (the rules and the inputs are in PFSessionEffort544.swift, unit-tested) and reads the week again.

struct PFSessionEffortCard544: View {
    let item: PFPlanWeekDoc.Item
    let sessionID: String

    @StateObject private var runner = PFPlanEditRunner529()
    @State private var form: PFSessionEffortForm544
    @State private var note: String?
    /// True from a save the server took until the week document arrives with the new values.
    @State private var awaitsRefresh = false
    private let hiding = PFHiding()

    init(item: PFPlanWeekDoc.Item, sessionID: String) {
        self.item = item
        self.sessionID = sessionID
        _form = State(initialValue: PFSessionEffortForm544(item: item, sessionID: sessionID))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PFWeekOverline529(text: PFSessionEffort544.sectionTitle)
            effortBlock
            minutesBlock
            if let problem = form.problem { PFWeekSub529(text: problem) }
            PFEditMessage529(runner: runner)
            if let note {
                PFWeekSub529(text: note).accessibilityIdentifier("plan544-effort-note")
            }
            buttons
        }
        .pfWeekCard()
        .containerIdentifier("plan544-effort")
        // The week document changed under the card: take its values unless the athlete is in the middle of a change.
        .onChange(of: item) { _, now in
            if awaitsRefresh || !form.hasChanges {
                form = PFSessionEffortForm544(item: now, sessionID: sessionID)
                awaitsRefresh = false
            }
        }
    }

    // MARK: Effort

    private var effortBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueLine(title: "Effort", value: form.effortWord ?? PFSessionEffort544.notSetWord, source: form.effortLabel,
                      isYours: form.effortSource == .yours, identifier: "plan544-effort-value")
            LookFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(PFEffortChoice544.allCases, id: \.self) { choice in
                    PFWeekButton529(title: choice.title, isProminent: form.effort == choice, isDisabled: runner.isBusy,
                                    identifier: "plan544-effort-\(choice.rawValue)") {
                        form.effort = choice
                        note = nil
                        runner.clear()
                    }
                    .accessibilityAddTraits(form.effort == choice ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Effort")
        }
    }

    // MARK: Minutes

    private var minutesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueLine(title: "Minutes", value: form.minutesShown.map { "\($0) min" } ?? PFSessionEffort544.notSetWord,
                      source: form.minutesLabel, isYours: form.minutesSource == .yours, identifier: "plan544-minutes-value")
            Stepper(value: minutesBinding, in: PFSessionEffort544.minMinutes...PFSessionEffort544.maxMinutes,
                    step: PFSessionEffort544.minutesStep) {
                Text("Change minutes")
                    .font(PFPlanFont543.text(16, weight: .regular))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minHeight: 44)
            .disabled(runner.isBusy)
            .accessibilityLabel("Minutes")
            .accessibilityValue(minutesSpoken)
            .accessibilityIdentifier("plan544-minutes-stepper")
        }
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { min(max(form.minutesShown ?? PFSessionEffort544.defaultMinutes, PFSessionEffort544.minMinutes), PFSessionEffort544.maxMinutes) },
            set: { form.minutes = $0; note = nil; runner.clear() })
    }

    private var minutesSpoken: String {
        guard let minutes = form.minutesShown else { return PFSessionEffort544.notSetWord }
        return "\(minutes) minutes, \(form.minutesLabel)"
    }

    /// "Moderate" with "Your choice" or "Estimated" beside it; one VoiceOver sentence.
    private func valueLine(title: String, value: String, source: String, isYours: Bool, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(PFPlanFont543.text(16, weight: .medium))
                .foregroundStyle(NoopLook.textPrimary)
            Text(hiding.text(value))
                .font(PFPlanFont543.text(16, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
            Spacer(minLength: 6)
            Text(source)
                .font(PFPlanFont543.text(15, weight: isYours ? .semibold : .regular))
                .foregroundStyle(isYours ? PFWeekColor529.teal : NoopLook.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(hiding.text(value)), \(source)")
        .accessibilityIdentifier(identifier)
    }

    // MARK: Buttons

    private var buttons: some View {
        LookFlowLayout(spacing: 8, lineSpacing: 8) {
            PFWeekButton529(title: runner.isBusy ? "Saving" : PFSessionEffort544.saveTitle, isProminent: true,
                            isDisabled: runner.isBusy || !form.canSend, identifier: "plan544-effort-save") {
                Task { await send(form.inputs(), reset: false) }
            }
            if form.hasChoice {
                PFWeekButton529(title: PFSessionEffort544.resetTitle, isDisabled: runner.isBusy, identifier: "plan544-effort-reset") {
                    Task { await send(form.resetInputs(), reset: true) }
                }
            }
        }
    }

    // MARK: Job

    /// Posts `session-effort`. A refusal or a missing connection leaves the card as typed with the server's own sentence under it.
    @MainActor private func send(_ inputs: [String: Any]?, reset: Bool) async {
        guard await runner.run(.sessionEffort, inputs: inputs) else { return }
        form = reset ? form.afterReset() : form.afterSaving()
        awaitsRefresh = true
        let said = reset ? PFSessionEffort544.resetNote : PFSessionEffort544.savedNote
        note = said
        UIAccessibility.post(notification: .announcement, argument: said)
        await PFUnified.model.refresh()
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
    }
}
