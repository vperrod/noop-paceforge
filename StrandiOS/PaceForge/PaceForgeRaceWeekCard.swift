import SwiftUI
import StrandDesign

/// PaceForge Today during race week: the phase, days to go, the volume target, the server's notes, the
/// carb-load line, a checklist you tick on this iPhone and the race-morning timeline. It replaces the
/// plain race countdown while it shows. Colours stay neutral: nothing here is a verdict on the athlete.
struct PFRaceWeekCard: View {
    let week: PFRaceWeek
    let todayISO: String
    @State private var ticked: Set<String>

    init(week: PFRaceWeek, todayISO: String) {
        self.week = week
        self.todayISO = todayISO
        _ticked = State(initialValue: PFRaceWeekChecklist.checked(date: week.date ?? todayISO))
    }

    private var tickDate: String { week.date ?? todayISO }

    var body: some View {
        PFCard(title: "Race week", icon: "flag.checkered", info: PFExplainerID.raceWeek, trailing: {
            PFChip(text: week.phaseTitle, color: StrandPalette.accent)
                .accessibilityIdentifier("pf-race-week-phase")
        }) {
            VStack(alignment: .leading, spacing: 16) {
                header
                if !week.notes.isEmpty { notesBlock }
                if let carb = week.carbLoad { carbBlock(carb) }
                if !week.checklist.isEmpty { checklistBlock }
                if !week.raceMorning.isEmpty { morningBlock }
                if let recovery = week.recovery, let suggestion = recovery.suggestion { recoveryBlock(recovery, suggestion) }
            }
        }
        .accessibilityIdentifier("pf-race-week-card")
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            if let days = week.daysTo, week.phase != "recovery", days >= 0 {
                VStack(spacing: 0) {
                    Text("\(days)")
                        .font(StrandFont.rounded(40))
                        .foregroundStyle(StrandPalette.accent)
                    Text(days == 1 ? "day" : "days")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("pf-race-week-days")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(week.event.name)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = eventLine {
                    Text(line)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if let line = volumeLine {
                    Text(line)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.textSecondary)
                        .accessibilityIdentifier("pf-race-week-volume")
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var eventLine: String? {
        let bits = [week.event.date.map { PFFormat.dayTitle($0) },
                    week.event.goalTime.map { "goal \($0)" },
                    week.event.location].compactMap { $0 }
        return bits.isEmpty ? nil : bits.joined(separator: " \u{00B7} ")
    }

    private var volumeLine: String? {
        guard let target = week.volumeTargetPct else { return nil }
        var line = "Volume target \(Int(target.rounded())) %"
        if let cut = week.weekVolumeCutPct, cut > 0 { line += " \u{00B7} week cut \(Int(cut.rounded())) %" }
        return line
    }

    // MARK: Notes and carb load

    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(week.notes.enumerated()), id: \.offset) { _, note in bullet(note) }
        }
        .accessibilityIdentifier("pf-race-week-notes")
    }

    private func carbBlock(_ carb: PFRaceWeek.CarbLoad) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(carb.label ?? "Carb load").strandOverline()
            if let line = carb.line {
                Text(line)
                    .font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = carb.note { PFParagraph(note) }
            ForEach(Array(carb.tips.enumerated()), id: \.offset) { _, tip in bullet(tip) }
        }
        .accessibilityIdentifier("pf-race-carb")
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\u{2022}").foregroundStyle(StrandPalette.accent)
            Text(text)
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Checklist

    private var checklistBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Checklist").strandOverline()
                Spacer(minLength: 8)
                Text("\(week.checklist.filter { ticked.contains($0.id) }.count) of \(week.checklist.count)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityIdentifier("pf-race-check-count")
            }
            .padding(.bottom, 4)
            ForEach(week.checklist) { item in
                Button { ticked = PFRaceWeekChecklist.toggle(item.id, date: tickDate) } label: { checkRow(item) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-race-check-\(item.id)")
                    .accessibilityValue(ticked.contains(item.id) ? "Ticked" : "Not ticked")
                if item.id != week.checklist.last?.id { Divider().overlay(StrandPalette.hairline) }
            }
        }
        .accessibilityIdentifier("pf-race-checklist")
    }

    private func checkRow(_ item: PFRaceWeek.CheckItem) -> some View {
        let isTicked = ticked.contains(item.id)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(isTicked ? StrandPalette.accent : StrandPalette.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(isTicked ? StrandPalette.textTertiary : StrandPalette.textPrimary)
                    .strikethrough(isTicked)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let when = item.when {
                    Text(when)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Race morning and recovery

    private var morningBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Race morning").strandOverline()
            ForEach(week.raceMorning) { step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(step.whenText)
                        .font(StrandFont.caption.weight(.semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(width: 104, alignment: .leading)
                    Text(step.text)
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("pf-race-morning")
    }

    private func recoveryBlock(_ recovery: PFRaceWeek.Recovery, _ suggestion: String) -> some View {
        var title = "Recovery"
        if let day = recovery.day { title += recovery.ofDays.map { " \u{00B7} day \(day) of \($0)" } ?? " \u{00B7} day \(day)" }
        return VStack(alignment: .leading, spacing: 4) {
            Text(title).strandOverline()
            PFParagraph(suggestion)
        }
        .accessibilityIdentifier("pf-race-recovery")
    }
}
