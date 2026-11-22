import SwiftUI
import StrandDesign

/// Drawing 3.12: two sessions on one day. It names both, says which one is the coach's, and offers three ways out: keep both, move the class
/// to another day, skip the class. The coach's required session is never the one that moves or is skipped from here.
struct PFOverlapSheet543: View {
    let target: PFOverlapTarget543

    @Environment(\.dismiss) private var dismiss
    @StateObject private var runner = PFPlanEditRunner529()
    @State private var isMoving = false
    @State private var newDate: Date
    @State private var asksToSkip = false
    @State private var note: String?

    init(target: PFOverlapTarget543) {
        self.target = target
        _newDate = State(initialValue: PFFormat.date(PFFormat.addDays(target.day.date ?? PFAPI.todayISO, 1)))
    }

    private var pair: [PFPlanWeekDoc.Item] { PFOverlap543.sessions(on: target.day, with: target.item) }
    private var parts: (coach: PFPlanWeekDoc.Item?, other: PFPlanWeekDoc.Item?) { PFOverlap543.split(pair) }
    private var changeable: PFPlanWeekDoc.Item? { PFOverlap543.changeable(pair) }
    private var date: String { target.day.date ?? "" }
    private var newDay: String { PFFormat.isoString(newDate) }
    private var window: ClosedRange<Date> {
        let day: TimeInterval = 86_400
        return Date(timeIntervalSinceNow: -399 * day)...Date(timeIntervalSinceNow: 399 * day)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(PFOverlap543.intro(coach: parts.coach, other: parts.other))
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("plan529-overlap-intro")
                    ForEach(Array(pair.enumerated()), id: \.offset) { _, item in sessionCard(item) }
                    if let reason = PFPlanRow543.clean(target.item.overlap?.reason) {
                        Text("Week check: \(reason)")
                            .font(PFPlanFont543.text(15, weight: .regular))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("plan529-overlap-reason")
                    }
                    choices
                    PFEditMessage529(runner: runner)
                    if let note {
                        Text(note)
                            .font(PFPlanFont543.text(15, weight: .regular))
                            .foregroundStyle(NoopLook.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .lookScreenBackground()
            .navigationTitle(date.isEmpty ? "Overlap" : PFFormat.dayTitle(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") { dismiss() }
                        .font(PFPlanFont543.text(16, weight: .regular))
                        .accessibilityIdentifier("plan529-overlap-back")
                }
            }
        }
        .containerIdentifier("plan529-overlap")
        .confirmationDialog("Skip this session? It is removed from your plan.", isPresented: $asksToSkip, titleVisibility: .visible) {
            Button("Skip the class", role: .destructive) { Task { await skip() } }
            Button("Keep it", role: .cancel) {}
        }
    }

    private func sessionCard(_ item: PFPlanWeekDoc.Item) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title ?? "Session")
                .font(PFPlanFont543.text(17, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            PFPlanBadgeRow543(badges: PFPlanRow543.badges(item).filter { $0.tone != .overlap })
        }
        .pfWeekCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(PFPlanRow543.sentence(item, dow: target.day.dow))
    }

    @ViewBuilder private var choices: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFPlanButton543(title: PFOverlap543.keepBoth, isProminent: true, isDisabled: runner.isBusy,
                            identifier: "plan529-overlap-keep") { keepBoth() }
            if changeable != nil {
                PFPlanButton543(title: PFOverlap543.moveClass, isDisabled: runner.isBusy, identifier: "plan529-overlap-move") {
                    withAnimation(.easeInOut(duration: 0.2)) { isMoving.toggle() }
                }
                if isMoving { moveRow }
                PFPlanButton543(title: PFOverlap543.skipClass, isDisabled: runner.isBusy, identifier: "plan529-overlap-skip") {
                    asksToSkip = true
                }
            } else {
                Text("Your coach's session stays where it is. Move or skip the other one from its own screen.")
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var moveRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker("Move to", selection: $newDate, in: window, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(PFPlanFont543.text(16, weight: .regular))
                .accessibilityIdentifier("plan529-overlap-date")
            PFPlanButton543(title: "Move it", isProminent: true, isDisabled: runner.isBusy || newDay == date,
                            identifier: "plan529-overlap-move-go") {
                Task { await move() }
            }
        }
    }

    // MARK: Actions

    /// No server call: the pair is remembered on this phone, so the chip and the strip stop asking about it.
    private func keepBoth() {
        UserDefaults.standard.set(true, forKey: PFOverlap543.keptKey(date: target.day.date, title: target.item.title,
                                                                      overlap: target.item.overlap ?? PFPlanWeekDoc.Overlap()))
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        dismiss()
    }

    @MainActor private func move() async {
        guard let id = changeable?.sessionId, await runner.run(.calendarEdit, inputs: PFJobInputs.calendarMove(sessionID: id, to: newDay)) else { return }
        await finished("Moved to \(PFFormat.dayTitle(newDay)).")
    }

    @MainActor private func skip() async {
        guard let id = changeable?.sessionId, await runner.run(.calendarEdit, inputs: PFJobInputs.calendarDelete(sessionID: id)) else { return }
        await finished("Skipped. You can undo this under Week notes, Recently deleted.")
    }

    @MainActor private func finished(_ text: String) async {
        note = text
        await PFUnified.model.refresh()
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
        dismiss()
    }
}
