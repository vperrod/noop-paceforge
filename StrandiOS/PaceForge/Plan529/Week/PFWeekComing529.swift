import SwiftUI
import StrandDesign

/// W1: the coming (or current) week. Top to bottom: where the week sits in the season and why, the seven days at once, the hours, the
/// changes waiting, then every workout of the week written out as its own card, the coach field and the three buttons.
struct PFWeekComing529: View {
    let week: String
    let doc: PFPlanWeekDoc
    let header: PFWeekHeader529
    let hooks: PFWeekHooks529
    @ObservedObject var decisions: PFWeekDecisions529
    let reload: () async -> PFPlanWeekDoc?

    @ObservedObject private var model = PFUnified.model

    private var days: [PFPlanWeekDoc.Day] { doc.days ?? [] }
    private var hasChanges: Bool { !(doc.changes ?? []).isEmpty || !(doc.decided ?? []).isEmpty }

    /// Where "+ Add" puts a workout: today when it is in this week, else the first day.
    private var addDate: String {
        doc.strip?.first(where: { $0.today == true })?.date ?? doc.from ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            top
            if let hours = doc.hours { PFWeekHours529(hours: hours) }
            easyBanner
            if hasChanges {
                PFWeekChanges529(changes: doc.changes ?? [], decided: doc.decided ?? [], decisions: decisions)
            }
            ForEach(days.indices, id: \.self) { index in
                PFWeekDay529(week: week, day: days[index], isToday: isToday(days[index]), hooks: hooks)
            }
            PFWeekTellCoach529(currentDoc: doc, reload: reload)
            buttons
        }
    }

    private func isToday(_ day: PFPlanWeekDoc.Day) -> Bool {
        doc.strip?.first(where: { $0.date == day.date })?.today == true
    }

    // MARK: Top card

    private var top: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            PFWeekPills529(pills: pills)
            if let why = doc.why, !why.isEmpty {
                PFWeekBody529(text: why).accessibilityIdentifier("plan529-why")
            }
            PFWeekStrip529(days: doc.strip ?? [])
            PFWeekLegend529()
        }
        .pfWeekCard()
    }

    private var pills: [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = []
        if let pill = doc.phase?.pill { out.append((pill, PFWeekPhase529.color(doc.phase?.key))) }
        if let pill = doc.nextRace?.pill { out.append((pill, NoopLook.textTertiary)) }
        return out
    }

    // MARK: Easy mode

    /// The easy-mode row of the old Week screen, as one line: its state at a glance, a tap opens Change today where it is started,
    /// accepted and ended.
    @ViewBuilder private var easyBanner: some View {
        if let easy = model.snapshot?.easyMode, !easy.isIdle {
            Button { PFDeepLink529.open(.sheet(.changeToday)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "leaf").foregroundStyle(PFWeekColor529.teal).accessibilityHidden(true)
                    Text(easyText(easy))
                        .font(LookFont.text(14, weight: .medium))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .pfWeekCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan529-easy-banner")
        }
    }

    private func easyText(_ easy: PFEasyMode) -> String {
        guard let mode = easy.mode else { return "Easy mode \u{00B7} proposal waiting for your answer" }
        var text = "Easy mode \u{00B7} level \(mode.level)"
        if let day = mode.dayText { text += " \u{00B7} " + day.lowercased() }
        return text
    }

    // MARK: Buttons

    private var buttons: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            PFWeekButton529(title: "Not feeling 100 %", identifier: "plan529-not-100") {
                PFDeepLink529.open(.sheet(.changeToday))
            }
            PFWeekButton529(title: "Log a niggle", identifier: "plan529-niggle") {
                PFDeepLink529.open(.sheet(.changeToday))
            }
            PFWeekButton529(title: "+ Add", isDisabled: addDate.isEmpty, identifier: "plan529-add") {
                hooks.openSwap(PFSwapTarget529(week: week, date: addDate, sessionId: nil, title: nil, minutes: nil))
            }
        }
        .containerIdentifier("plan529-bottom-buttons")
    }
}
