import SwiftUI
import StrandDesign

/// "Tell the coach what to change...": the existing coach Change my plan job (`coach`), then the days it changed. Used under the week (W1)
/// and in the change-today sheet (W4).
struct PFWeekTellCoach529: View {
    /// The week on show, to find the days whose workouts changed. nil in the change-today sheet, which then reads the snapshot only.
    var currentDoc: PFPlanWeekDoc? = nil
    var reload: (() async -> PFPlanWeekDoc?)? = nil
    var idPrefix = "plan529-tell"

    @ObservedObject private var model = PFUnified.model
    @StateObject private var tracker = PFJobTracker()
    @State private var draft = ""
    @State private var reply: String?
    @State private var filed: [String] = []
    @State private var changedDays: [String] = []

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }
    private var canSend: Bool { !isBusy && PFJobInputs.coach(draft) != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Tell the coach what to change\u{2026}", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .font(LookFont.text(14.5, weight: .regular))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NoopLook.card))
                    .accessibilityIdentifier("\(idPrefix)-input")
                Button {
                    Task { await send() }
                } label: {
                    if isBusy {
                        ProgressView().frame(width: 44, height: 44)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(PFWeekColor529.teal)
                            .frame(width: 44, height: 44)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send the change to the coach")
                .accessibilityIdentifier("\(idPrefix)-send")
            }
            output
        }
        .containerIdentifier("\(idPrefix)-field")
    }

    @ViewBuilder private var output: some View {
        switch tracker.phase {
        case .sending, .working:
            HStack(spacing: 8) {
                ProgressView()
                PFWeekSub529(text: "Working on it. This can take a few minutes.")
            }
        case .failed(let message):
            Text(message)
                .font(LookFont.text(12.5, weight: .regular))
                .foregroundStyle(PFWeekColor529.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(idPrefix)-failed")
        case .done:
            outcome
        case .idle:
            PFWeekSub529(text: "In plain words: \"Move Thursday's class to Friday\", \"make this week easier\". Done at once, and you see the days that changed.")
        }
    }

    @ViewBuilder private var outcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reply ?? "Done.")
                .font(LookFont.text(14, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(idPrefix)-reply")
            if changedDays.isEmpty {
                PFWeekSub529(text: "No day of the plan changed.").accessibilityIdentifier("\(idPrefix)-days-none")
            } else {
                PFWeekOverline529(text: "Changed days")
                ForEach(changedDays, id: \.self) { day in
                    NavigationLink(value: TabRoute.planDay(day)) {
                        HStack {
                            Text(PFFormat.dayTitle(day))
                                .font(LookFont.text(14.5, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(NoopLook.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(idPrefix)-day-\(day)")
                }
            }
            if !filed.isEmpty {
                PFWeekSub529(text: "The coach filed these for you to look at:")
                ForEach(filed, id: \.self) { title in PFWeekSub529(text: "\u{2022} " + title) }
            }
        }
    }

    @MainActor private func send() async {
        guard let inputs = PFJobInputs.coach(draft) else { return }
        let previous = model.snapshot?.coach.chat.last(where: { $0.role == "coach" })?.ts
        let needsBefore = model.snapshot?.needsYou ?? []
        let weeksBefore = model.snapshot?.weeks ?? []
        let docBefore = currentDoc
        reply = nil
        filed = []
        changedDays = []
        guard case .success = await tracker.run(.coach, inputs: inputs) else { return }
        draft = ""
        await model.refresh()
        reply = PFCoachInstruction.reply(in: model.snapshot?.coach.chat ?? [], after: previous)
        filed = PFCoachInstruction.newProposals(before: needsBefore, after: model.snapshot?.needsYou ?? [])
        var days = Set(PFPlanDiff.changedDays(before: weeksBefore, after: model.snapshot?.weeks ?? []))
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        if let reload, let docAfter = await reload() {
            days.formUnion(Self.changedDays(before: docBefore, after: docAfter))
        }
        changedDays = days.sorted()
    }

    /// The days of the week document whose workouts differ: one added, dropped, moved, renamed, resized or given another state.
    static func changedDays(before: PFPlanWeekDoc?, after: PFPlanWeekDoc) -> [String] {
        guard let before else { return [] }
        func signatures(_ doc: PFPlanWeekDoc) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for day in doc.days ?? [] {
                guard let date = day.date else { continue }
                out[date] = (day.items ?? []).map { item in
                    [item.sessionId ?? "", item.title ?? "", item.kind ?? "", item.status ?? "",
                     String(item.minutes ?? 0), item.effort ?? ""].joined(separator: "|")
                }.sorted()
            }
            return out
        }
        let old = signatures(before)
        let new = signatures(after)
        return Set(old.keys).union(new.keys).filter { (old[$0] ?? []) != (new[$0] ?? []) }.sorted()
    }
}
