import SwiftUI
import StrandDesign

/// What the Change workout sheet (W5) is opened for: replace this session, or add a workout on this day (no session id).
struct PFSwapTarget529: Identifiable, Equatable {
    let week: String
    /// The day, `yyyy-MM-dd`.
    let date: String
    let sessionId: String?
    let title: String?
    let minutes: Int?
    let againChangeId: String?

    init(week: String, date: String, sessionId: String?, title: String?, minutes: Int?, againChangeId: String? = nil) {
        self.week = week
        self.date = date
        self.sessionId = sessionId
        self.title = title
        self.minutes = minutes
        self.againChangeId = againChangeId
    }

    var id: String { "\(date)-\(sessionId ?? "add")" }
    var isAdd: Bool { sessionId == nil }
}

enum PFSwapKind529: String, CaseIterable, Identifiable {
    case hyrox, strength, run, bike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hyrox: return "HYROX conditioning"
        case .strength: return "Strength"
        case .run: return "Running"
        case .bike: return "Cycling"
        }
    }

    var icon: String {
        switch self {
        case .hyrox: return "flame"
        case .strength: return "dumbbell"
        case .run: return "figure.run"
        case .bike: return "bicycle"
        }
    }
}

/// W5, Change workout: pick what you would rather do, the coach builds it from the week (job `session-swap`, a fast job: the reply names the change and the week
/// document is already rewritten), and the answer opens as a change (W3 layout) with Accept, Try another and Keep the original. A day with no
/// session reads "Add a workout" and the accepted result is added instead of replacing.
struct PFChangeWorkoutSheet529: View {
    let target: PFSwapTarget529

    private enum Phase {
        case choosing
        case building
        case result(PFPlanWeekDoc.Change)
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var tracker = PFJobTracker()
    @State private var phase = Phase.choosing
    @State private var kind: PFSwapKind529?
    /// nil is "Same length".
    @State private var minutes: Int?

    private var heading: String { target.isAdd ? "Add a workout" : "Change workout" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("plan529-swap-done")
                }
            }
        }
        .containerIdentifier("plan529-swap")
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .choosing:
            chooser
        case .building:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("The coach is building it\u{2026}")
                        .font(LookFont.text(15, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                }
                PFWeekSub529(text: "It uses your week, your readings and what you still need. This can take a minute.")
            }
            .pfWeekCard()
            .accessibilityIdentifier("plan529-swap-building")
        case .result(let change):
            Text(change.sheetTitle ?? change.title ?? heading)
                .font(LookFont.text(20, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PFChangeContent529(change: change, onAccepted: { dismiss() }, onKept: { dismiss() },
                               onTryAnother: { Task { await ask(again: change.id) } }, onAskCoach: {})
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Text(message)
                    .font(LookFont.text(14, weight: .regular))
                    .foregroundStyle(PFWeekColor529.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-swap-failed")
                PFWeekButton529(title: "Try again", identifier: "plan529-swap-retry") { phase = .choosing }
            }
            .pfWeekCard()
        }
    }

    // MARK: Choosing

    private var chooser: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFWeekTellCoach529(idPrefix: "plan529-edit-text", sessionID: target.sessionId,
                               targetDate: target.date)
                .pfWeekCard()
            Text("What would you rather do?")
                .font(LookFont.text(20, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
            if let title = target.title, !target.isAdd {
                PFWeekSub529(text: "Now: \(title) on \(PFFormat.dayTitle(target.date)). It stays as it is until you accept the new one.")
            } else {
                PFWeekSub529(text: "\(PFFormat.dayTitle(target.date)). The coach adds it only when you accept.")
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(PFSwapKind529.allCases) { option in kindCard(option) }
            }
            VStack(alignment: .leading, spacing: 8) {
                PFWeekOverline529(text: "How long")
                LookFlowLayout(spacing: 6, lineSpacing: 6) {
                    lengthChip(nil, "Same length", id: "same")
                    lengthChip(30, "30 min", id: "30")
                    lengthChip(45, "45 min", id: "45")
                    lengthChip(60, "60 min", id: "60")
                }
            }
            PFWeekButton529(title: "Ask the coach", isProminent: true, isDisabled: kind == nil, identifier: "plan529-swap-ask") {
                Task { await ask(again: nil) }
            }
        }
        .containerIdentifier("plan529-swap-choose")
    }

    private func kindCard(_ option: PFSwapKind529) -> some View {
        let isSelected = kind == option
        return Button { kind = option } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: option.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? PFWeekColor529.teal : NoopLook.textSecondary)
                    .accessibilityHidden(true)
                Text(option.title)
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NoopLook.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? PFWeekColor529.teal : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("plan529-swap-kind-\(option.rawValue)")
    }

    private func lengthChip(_ value: Int?, _ title: String, id: String) -> some View {
        let isSelected = minutes == value
        return Button { minutes = value } label: {
            Text(title)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isSelected ? Color(hex: "#06231A") : NoopLook.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous).fill(isSelected ? PFWeekColor529.teal : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(isSelected ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("plan529-swap-len-\(id)")
    }

    // MARK: Asking

    /// Posts `session-swap`, then reads the week document the server rewrote before it answered and opens the change it filed.
    @MainActor private func ask(again: String?) async {
        guard let kind,
              let inputs = PFJobInputs.sessionSwap(date: target.date, sessionID: target.sessionId, kind: kind.rawValue,
                                                   minutes: minutes, again: again ?? target.againChangeId) else { return }
        phase = .building
        switch await tracker.run(.sessionSwap, inputs: inputs) {
        case .failure(let error):
            phase = .failed(error.message)
        case .success(let result):
            guard let changeId = result["change_id"].text else {
                phase = .failed("The coach did not send a change back. Try again.")
                return
            }
            let week = result["week"].text ?? target.week
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
            if let doc = await PFWeekFetch529.week(week), let change = doc.changes?.first(where: { $0.id == changeId }) {
                PFChangeLookup529.remember(doc)
                phase = .result(change)
            } else {
                phase = .failed("The change is not on your plan yet. Close this and look at the week in a moment.")
            }
        }
    }
}
