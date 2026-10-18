import SwiftUI
import StrandDesign

/// One session as PaceForge shows it: a collapsed row that opens to the full plan detail
/// (why, structure, steps, strength movements, versus-the-plan). A completed session with a matched
/// Garmin activity opens its results instead.
struct PFWorkoutRow: View {
    let workout: PFWorkout
    let snapshot: PFSnapshot
    @State private var isOpen = false
    @State private var showResults = false

    var body: some View {
        StrandCard(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if workout.hasResults {
                        showResults = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pf-workout-\(workout.id)")
                .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

                if isOpen {
                    PFWorkoutDetail(workout: workout)
                        .padding(.top, 14)
                }
            }
        }
        .opacity(workout.status == "optional" ? 0.72 : 1)
        .sheet(isPresented: $showResults) {
            PFResultsSheet(workout: workout, snapshot: snapshot)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(PFColor.workout(workout.kind))
                .frame(width: 4)
                .frame(minHeight: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(workout.name ?? "Workout")
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !targetLine.isEmpty {
                    Text(targetLine)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
                if PFWorkoutBadges.hasAny(workout, snapshot) { PFWorkoutBadges(workout: workout, snapshot: snapshot) }
                if !isOpen, let why = purposeLine {
                    Text(why)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                PFChip(text: workout.status, color: PFColor.status(workout.status))
                Image(systemName: workout.hasResults ? "chevron.right" : "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .rotationEffect(.degrees(isOpen && !workout.hasResults ? 180 : 0))
            }
        }
        .contentShape(Rectangle())
    }

    private var targetLine: String {
        var bits: [String] = []
        if let km = workout.distanceKm { bits.append("\(PFFormat.oneDecimal(km)) km") }
        if let min = workout.durationMin { bits.append("\(Safe.int(min)) min") }
        if let rpe = workout.targetRpe { bits.append("RPE \(PFFormat.trimmed(rpe))") }
        return bits.joined(separator: " \u{00B7} ")
    }

    private var purposeLine: String? { workout.briefing?.purpose ?? workout.description }
}

struct PFWorkoutDetail: View {
    let workout: PFWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider().overlay(StrandPalette.hairline)

            HStack(spacing: 8) {
                PFChip(text: PFFormat.words(workout.kind ?? "session"), color: PFColor.workout(workout.kind))
                if let rpe = workout.userRpe {
                    PFChip(text: "Your RPE \(PFFormat.trimmed(rpe))", color: StrandPalette.accent)
                }
                if let cadence = workout.cadenceTarget {
                    PFChip(text: "Cadence \(PFFormat.trimmed(cadence)) spm", color: StrandPalette.accent)
                }
            }

            if let description = workout.description { PFParagraph(description) }

            if let b = workout.briefing {
                if let t = b.purpose { PFLabeled(label: "Why this session", text: t) }
                if let t = b.structure { PFLabeled(label: "Structure", text: t) }
                if let t = b.feel { PFLabeled(label: "How it should feel", text: t) }
                if let t = b.ifWrong { PFLabeled(label: "If it goes wrong", text: t) }
                if let t = b.cue { PFLabeled(label: "Form cue", text: t) }
                if let t = b.venue { PFLabeled(label: "Venue", text: t) }
                if let t = b.fuel { PFLabeled(label: "Fueling", text: t) }
                if let t = b.warmup { PFLabeled(label: "Warm-up", text: t) }
            }

            if !workout.steps.isEmpty {
                PFStepList(steps: workout.steps, workout: workout)
            }

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Strength movements").strandOverline()
                    ForEach(Array(workout.exercises.enumerated()), id: \.offset) { _, e in
                        PFExerciseRow(exercise: e)
                    }
                }
            }

            if let c = workout.compliance { PFComplianceView(compliance: c) }

            if let analysis = workout.completionAnalysis {
                Text(analysis)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
            }

            if let notes = workout.notes {
                Text(notes)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Steps

struct PFStepList: View {
    let steps: [PFStep]
    let workout: PFWorkout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session breakdown").strandOverline()
            ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                if let reps = step.repeatCount, !step.steps.isEmpty {
                    let inner = step.steps
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text("\(reps) \u{00D7}")
                                .font(StrandFont.rounded(15))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Text(blockTitle(step))
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textSecondary)
                        }
                        ForEach(Array(inner.enumerated()), id: \.offset) { _, s in PFStepRow(step: s) }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(StrandPalette.surfaceInset))
                } else {
                    PFStepRow(step: step)
                }
            }
            totals
        }
    }

    private func blockTitle(_ step: PFStep) -> String {
        let d = (step.description ?? "repeat")
        return d.range(of: "^Repeat x\\d+$", options: [.regularExpression, .caseInsensitive]) != nil ? "repeat" : d
    }

    @ViewBuilder private var totals: some View {
        let bits: [String] = [
            workout.distanceKm.map { "Total \(PFFormat.oneDecimal($0)) km" },
            workout.durationMin.map { "~\(Safe.int($0)) min" },
            workout.cadenceTarget.map { "Cadence \(PFFormat.trimmed($0)) spm" },
        ].compactMap { $0 }
        if !bits.isEmpty {
            Text(bits.joined(separator: " \u{00B7} "))
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

struct PFStepRow: View {
    let step: PFStep

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(meta.color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(meta.label)
                    .font(StrandFont.overline)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(what)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                if !quantity.isEmpty {
                    Text(quantity)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                if !target.isEmpty {
                    Text(target)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }

    private var meta: (label: String, color: Color) {
        switch step.type ?? "" {
        case "warmup": return ("Warm up", PFColor.sky)
        case "cooldown": return ("Cool down", PFColor.sky)
        case "interval": return ("Work", PFColor.critical)
        case "active": return ("Run", PFColor.positive)
        case "recovery": return ("Recover", PFColor.warning)
        case "rest": return ("Rest", StrandPalette.textTertiary)
        default: return (PFFormat.capitalized(step.type ?? "Step"), StrandPalette.textTertiary)
        }
    }

    private var what: String {
        let d = (step.description ?? "").trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? meta.label : d
    }

    private var quantity: String {
        if let m = step.distanceM {
            if m >= 1000 {
                let km = m / 1000
                return (km.rounded() == km ? String(Safe.int(km)) : String(format: "%.2f", km)) + " km"
            }
            return "\(Safe.int(m)) m"
        }
        if let s = step.durationSec {
            let secs = Safe.int(s)
            if secs < 60 { return "\(secs) s" }
            return secs % 60 == 0 ? "\(secs / 60) min" : String(format: "%d:%02d min", secs / 60, secs % 60)
        }
        return ""
    }

    private var target: String {
        guard let low = step.targetLow else { return "" }
        let high = step.targetHigh
        let hasRange = high != nil && high != low
        switch step.targetType ?? "" {
        case "heart_rate":
            return "\(Safe.int(low))" + (hasRange ? "\u{2013}\(Safe.int((high ?? low)))" : "") + " bpm"
        case "power":
            return "\(Safe.int(low))" + (hasRange ? "\u{2013}\(Safe.int((high ?? low)))" : "") + " W"
        default:
            let a = min(low, high ?? low), b = max(low, high ?? low)
            return PFFormat.pace(a) + (a != b ? "\u{2013}\(PFFormat.pace(b))" : "") + "/km"
        }
    }
}

// MARK: Strength + compliance

struct PFExerciseRow: View {
    let exercise: PFExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise.name)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer(minLength: 8)
                Text(prescription)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if let cue = exercise.cue, !cue.isEmpty {
                Text(cue)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var prescription: String {
        var bits: [String] = []
        if let sets = exercise.sets, let reps = exercise.reps { bits.append("\(Safe.int(sets, .towardZero)) \u{00D7} \(reps)") }
        else if let reps = exercise.reps { bits.append(reps) }
        if let rpe = exercise.rpe { bits.append("RPE \(PFFormat.trimmed(rpe))") }
        return bits.joined(separator: " \u{00B7} ")
    }
}

struct PFComplianceView: View {
    let compliance: PFCompliance

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Versus the plan").strandOverline()
            if compliance.status == "red" {
                Text("Missed \u{2014} no matching activity")
                    .font(StrandFont.subhead)
                    .foregroundStyle(PFColor.critical)
            } else {
                HStack(spacing: 10) {
                    PFChip(text: chipText, color: color)
                    if let line = line(compliance.actualKm, compliance.plannedKm, "km") {
                        Text(line).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                    if let line = line(compliance.actualMin, compliance.plannedMin, "min") {
                        Text(line).font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    }
                }
            }
        }
    }

    private var label: String {
        switch compliance.status ?? "" {
        case "green": return "on plan"
        case "yellow": return "off plan"
        case "orange": return "way off"
        default: return "missed"
        }
    }

    private var chipText: String {
        if let ratio = compliance.ratio { return "\(Safe.int((ratio * 100)))% \u{00B7} \(label)" }
        return label
    }

    private var color: Color {
        switch compliance.status ?? "" {
        case "green": return PFColor.positive
        case "yellow", "orange": return PFColor.warning
        default: return PFColor.critical
        }
    }

    private func line(_ actual: Double?, _ planned: Double?, _ unit: String) -> String? {
        guard actual != nil || planned != nil else { return nil }
        let a = actual.map { PFFormat.trimmed($0) } ?? "\u{2014}"
        let p = planned.map { PFFormat.trimmed($0) } ?? "\u{2014}"
        return "\(a) of \(p) \(unit)"
    }
}
