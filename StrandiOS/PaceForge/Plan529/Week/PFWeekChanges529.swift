import SwiftUI
import StrandDesign

/// "N changes waiting for you": one line each with Accept, Keep and Why, "Accept all N", and what the athlete already decided.
struct PFWeekChanges529: View {
    let changes: [PFPlanWeekDoc.Change]
    let decided: [String]
    @ObservedObject var decisions: PFWeekDecisions529

    private var ids: [String] { changes.compactMap { $0.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !changes.isEmpty {
                PFWeekOverline529(text: changes.count == 1 ? "1 change waiting for you" : "\(changes.count) changes waiting for you")
                ForEach(changes.indices, id: \.self) { index in
                    if index > 0 { Divider().overlay(NoopLook.divider) }
                    row(changes[index])
                }
                if changes.count > 1 {
                    PFWeekButton529(title: "Accept all \(changes.count)", isProminent: true, isDisabled: decisions.isBusy,
                                    identifier: "plan529-accept-all") {
                        Task { await decisions.acceptAll(ids) }
                    }
                }
                if let failure = decisions.failure {
                    Text(failure)
                        .font(PFPlanFont543.text(12.5, weight: .regular))
                        .foregroundStyle(PFWeekColor529.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-changes-failed")
                }
            }
            ForEach(decided.indices, id: \.self) { index in
                PFWeekSub529(text: decided[index]).accessibilityIdentifier("plan529-decided-\(index)")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-changes")
    }

    private func row(_ change: PFPlanWeekDoc.Change) -> some View {
        let id = change.id ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.title ?? "")
                    .font(PFPlanFont543.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = change.oneLine, !line.isEmpty { PFWeekSub529(text: line) }
            }
            LookFlowLayout(spacing: 6, lineSpacing: 6) {
                PFWeekButton529(title: change.acceptLabel ?? "Accept", isProminent: true, isDisabled: decisions.isBusy,
                                identifier: "plan529-change-accept-\(id)") {
                    Task { await decisions.decide(id, accept: true) }
                }
                PFWeekButton529(title: shortKeep(change), isDisabled: decisions.isBusy, identifier: "plan529-change-keep-\(id)") {
                    Task { await decisions.decide(id, accept: false) }
                }
                PFWeekButton529(title: "Why", identifier: "plan529-change-why-\(id)") {
                    PFDeepLink529.open(.sheet(.change(id: id)))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan529-change-row-\(id)")
    }

    /// The drawings say "Keep" (or "No" for an addition); the full label ("Keep 45 min") lives on the change sheet.
    private func shortKeep(_ change: PFPlanWeekDoc.Change) -> String {
        let label = change.keepLabel ?? "Keep"
        return label.lowercased().hasPrefix("keep") ? "Keep" : label
    }
}
