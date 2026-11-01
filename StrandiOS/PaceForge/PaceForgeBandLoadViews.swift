#if os(iOS)
import SwiftUI
import StrandDesign

// The load cards on Insights > Deep dives (see PaceForgeBandReport.swift for the numbers): the weekly target-load range, Garmin's Load
// Focus and muscular load. Every sentence is the server's own, shown as served (the Hide numbers switch applies); each card says whose
// numbers it holds and leaves out when the server sends nothing.

// MARK: - A range with a marker

/// A track with the usual range drawn on it and one marker. `bar` positions are 0 to 1.
struct PFRangeTrack: View {
    let bar: PFBandLogic.Bar
    var color: Color = NoopLook.rest

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(NoopLook.track)
                Capsule()
                    .fill(color.opacity(0.45))
                    .frame(width: max(width * CGFloat(bar.high - bar.low), 4))
                    .offset(x: width * CGFloat(bar.low))
                Circle()
                    .fill(NoopLook.textPrimary)
                    .frame(width: 12, height: 12)
                    .offset(x: min(max(width * CGFloat(bar.value) - 6, 0), width - 12))
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }
}

// MARK: - Insights > Form: the load panels

/// The weekly target range, Garmin's Load Focus and muscular load, one after the other; each leaves out when the server sends none.
struct PFLoadPanels: View {
    let insights: PFInsights

    var body: some View {
        Group {
            if let target = insights.weekTarget { PFWeekTargetCard(target: target) }
            if let focus = insights.loadFocus { PFLoadFocusCard(focus: focus) }
            if let muscular = insights.muscular { PFMuscularLoadCard(load: muscular) }
        }
    }
}

private func pfWeekStatusColor(_ status: String?) -> Color {
    switch status {
    case "in_range": return PFColor.positive
    case "under": return PFColor.warning
    case "over": return PFColor.critical
    default: return PFColor.sky
    }
}

struct PFWeekTargetCard: View {
    let target: PFWeekTarget

    var body: some View {
        PFCard("Weekly load target", icon: "chart.bar.fill") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(target.weeks) { week in PFWeekTargetRow(week: week) }
                if let source = target.source {
                    Text(source)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                if let note = target.note { PFParagraph(note) }
            }
        }
        .containerIdentifier("pf-week-target")
    }
}

private struct PFWeekTargetRow: View {
    let week: PFWeekTargetWeek

    private var title: LocalizedStringKey {
        if week.state == "current" { return "This week" }
        return "Next week"
    }

    private var bar: PFBandLogic.Bar? {
        guard let value = week.actual ?? week.expected, week.low != nil || week.high != nil else { return nil }
        return PFBandLogic.bar(value: value, low: week.low, high: week.high)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                if let word = PFBandLogic.weekStatusWord(week.status) { PFChip(text: word, color: pfWeekStatusColor(week.status)) }
                if let word = PFBandLogic.plannedCheckWord(week.plannedCheck) {
                    PFChip(text: word, color: pfWeekStatusColor(week.plannedCheck))
                }
            }
            if let bar { PFRangeTrack(bar: bar, color: pfWeekStatusColor(week.status ?? week.plannedCheck)) }
            if let line = week.line { PFParagraph(line) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-week-target-\(week.state)")
    }
}

struct PFLoadFocusCard: View {
    let focus: PFLoadFocus

    var body: some View {
        PFCard("Load Focus, Garmin's view", icon: "gauge") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(focus.buckets) { bucket in PFLoadBucketRow(bucket: bucket) }
                if let verdict = focus.verdict { PFParagraph(verdict) }
                if let note = focus.note {
                    Text(note)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .containerIdentifier("pf-load-focus")
    }
}

private struct PFLoadBucketRow: View {
    let bucket: PFLoadBucket

    private var bar: PFBandLogic.Bar? { PFBandLogic.bar(value: bucket.value, low: bucket.min, high: bucket.max) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(bucket.label).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text(String(Safe.int(bucket.value))).font(LookFont.numeral(20)).foregroundStyle(NoopLook.textPrimary)
                if let word = PFBandLogic.bucketWord(bucket.status) { PFChip(text: word, color: pfWeekStatusColor(bucket.status)) }
            }
            if let bar { PFRangeTrack(bar: bar, color: pfWeekStatusColor(bucket.status)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-load-focus-\(bucket.key)")
    }
}

struct PFMuscularLoadCard: View {
    let load: PFMuscularLoad

    var body: some View {
        PFCard("Muscular load", icon: "dumbbell.fill") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(load.top) { group in PFMuscleGroupRow(group: group) }
                PFMuscularWeeks(weeks: load.weekly)
                if load.calibrating {
                    Text("Calibrating: under four weeks of sets, so the ratios are rough.")
                        .font(LookFont.text(12.5, weight: .semibold))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                if let note = load.note { PFParagraph(note) }
                if let source = load.source {
                    Text(source)
                        .font(LookFont.text(12, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .containerIdentifier("pf-muscular-load")
    }
}

private struct PFMuscleGroupRow: View {
    let group: PFMuscleGroup

    private var color: Color {
        switch group.status {
        case "spike": return PFColor.critical
        case "above": return PFColor.warning
        case "steady": return PFColor.positive
        default: return PFColor.sky
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(group.label).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text("\(group.acuteSets) sets").font(LookFont.numeral(18)).foregroundStyle(NoopLook.textPrimary)
                if let word = PFBandLogic.ratioWord(group.status) { PFChip(text: word, color: color) }
            }
            if let line = group.line { PFParagraph(line) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-muscle-\(group.key)")
    }
}

/// Sets per week, oldest first, as bars the height of the busiest week shown.
private struct PFMuscularWeeks: View {
    let weeks: [PFMuscularWeek]

    private var busiest: Int { max(weeks.map { $0.sets }.max() ?? 0, 1) }

    var body: some View {
        if weeks.count > 1 {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(weeks) { week in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(NoopLook.rest.opacity(0.6))
                        .frame(height: max(4, 44 * CGFloat(week.sets) / CGFloat(busiest)))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Week ending \(week.weekEnding)")
                        .accessibilityValue("\(week.sets) sets")
                }
            }
            .frame(height: 44, alignment: .bottom)
            .containerIdentifier("pf-muscular-weeks")
        }
    }
}
#endif
