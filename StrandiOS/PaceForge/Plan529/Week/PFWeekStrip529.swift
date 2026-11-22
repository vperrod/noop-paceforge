import SwiftUI
import StrandDesign

/// The seven days at once: one column a day, one bar a workout. Bar height is minutes, colour is effort; an outline is planned, a dashed
/// outline is optional, a solid bar is done.
struct PFWeekStrip529: View {
    let days: [PFPlanWeekDoc.StripDay]

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                PFWeekStripDay529(day: day)
            }
        }
        .containerIdentifier("plan529-strip")
    }
}

struct PFWeekStripDay529: View {
    let day: PFPlanWeekDoc.StripDay

    private var bars: [PFPlanWeekDoc.Bar] { Array((day.bars ?? []).reversed()) }
    private var isToday: Bool { day.today == true }

    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 3) {
                Spacer(minLength: 0)
                ForEach(bars.indices, id: \.self) { index in
                    PFWeekBar529(bar: bars[index])
                }
            }
            .frame(height: 66)
            Text(day.dow ?? "")
                .pfCaps(11, weight: .semibold)
                .foregroundStyle(isToday ? PFWeekColor529.teal : NoopLook.textSecondary)
            Text(day.label ?? "")
                .font(PFPlanFont543.text(10, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(day.dow ?? "") \(day.label ?? "")")
        .accessibilityIdentifier("plan529-strip-day-\(day.date ?? "")")
    }
}

struct PFWeekBar529: View {
    let bar: PFPlanWeekDoc.Bar

    private var height: CGFloat { max(6, min(64, CGFloat(bar.minutes ?? 0) * 0.58)) }

    var body: some View {
        shape
            .frame(height: height)
            .padding(.horizontal, 6)
    }

    @ViewBuilder private var shape: some View {
        let color = PFWeekColor529.effort(bar.effort)
        switch bar.state ?? "planned" {
        case "done":
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color)
        case "optional":
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(NoopLook.textSecondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        case "missed":
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(PFWeekColor529.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
        default:
            RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(color, lineWidth: 1.5)
        }
    }
}

/// The legend under the strip.
struct PFWeekLegend529: View {
    var body: some View {
        LookFlowLayout(spacing: 12, lineSpacing: 4) {
            dot(PFWeekColor529.amber, "hard")
            dot(PFWeekColor529.blue, "moderate")
            dot(PFWeekColor529.teal, "easy")
            Text("dashed = optional")
                .font(PFPlanFont543.text(11.5, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
        }
        .accessibilityIdentifier("plan529-legend")
    }

    private func dot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(PFPlanFont543.text(11.5, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
        }
    }
}

/// Hours this week: firm, optional, the coach's limit as a marker, your target.
struct PFWeekHours529: View {
    let hours: PFPlanWeekDoc.Hours

    private var scale: Double { max(hours.target ?? 0, hours.aim ?? 0, hours.planned ?? 0, hours.done ?? 0, 1) }

    private func fraction(_ value: Double?) -> CGFloat {
        CGFloat(min(max((value ?? 0) / scale, 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFWeekOverline529(text: "Hours this week").accessibilityIdentifier("plan529-hours-title")
            gauge
            labels
            if let note = hours.note, !note.isEmpty { PFWeekSub529(text: note) }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-hours")
    }

    private var gauge: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(NoopLook.row)
                HStack(spacing: 0) {
                    Rectangle().fill(PFWeekColor529.blue).frame(width: width * fraction(hours.firm))
                    Rectangle().fill(NoopLook.textTertiary.opacity(0.45)).frame(width: width * fraction(hours.optional))
                }
                .clipShape(Capsule())
                if hours.aim != nil {
                    Rectangle()
                        .fill(NoopLook.textPrimary)
                        .frame(width: 2, height: 22)
                        .offset(x: max(0, width * fraction(hours.aim) - 1))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }

    private var labels: some View {
        LookFlowLayout(spacing: 12, lineSpacing: 4) {
            pair(bold: hours.firmLabel, lead: nil, tail: "firm")
            pair(bold: hours.optionalLabel, lead: nil, tail: "optional")
            pair(bold: hours.aimLabel, lead: "coach's limit", tail: nil)
            pair(bold: hours.targetLabel, lead: "your target", tail: nil)
            pair(bold: hours.doneLabel, lead: nil, tail: "done")
        }
    }

    @ViewBuilder private func pair(bold: String?, lead: String?, tail: String?) -> some View {
        if let bold, !bold.isEmpty {
            HStack(spacing: 3) {
                if let lead { Text(lead).foregroundStyle(NoopLook.textSecondary) }
                Text(bold).fontWeight(.semibold).foregroundStyle(NoopLook.textPrimary)
                if let tail { Text(tail).foregroundStyle(NoopLook.textSecondary) }
            }
            .font(PFPlanFont543.text(11.5, weight: .regular))
        }
    }
}
