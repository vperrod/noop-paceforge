import SwiftUI
import StrandDesign

/// Screen 1e, "Every workout written out": the week's days, the booked sessions and the ones the coach filled in, marked proposed. A
/// session opens its own sheet (warm-up, main set, what to do on a red morning).
struct PFReviewWorkouts530: View {
    let week: String
    let number: String
    let doc: PFPlanWeekDoc

    private let hiding = PFHiding()
    private var days: [PFPlanWeekDoc.Day] { doc.days ?? [] }

    var body: some View {
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PFReviewSectionTitle530(text: "Week \(number) \u{00B7} every workout")
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(days.indices, id: \.self) { index in
                        if index > 0 { Divider().overlay(NoopLook.divider) }
                        dayRow(days[index])
                    }
                }
                .pfWeekCard()
                .containerIdentifier("review530-workouts")
                PFWeekSub529(text: "Tap a workout for warm-up, main set, cool-down and what to do on a red morning.")
            }
        }
    }

    private func dayRow(_ day: PFPlanWeekDoc.Day) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(day.title ?? "")
                .pfCaps(12, weight: .semibold)
                .foregroundStyle(NoopLook.textSecondary)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                ForEach((day.items ?? []).indices, id: \.self) { index in
                    item((day.items ?? [])[index], day: day)
                }
            }
        }
    }

    @ViewBuilder private func item(_ item: PFPlanWeekDoc.Item, day: PFPlanWeekDoc.Day) -> some View {
        let key = item.sessionId ?? day.date ?? ""
        if item.kind == "rest" || item.sessionId == nil {
            content(item, day: day)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(item.kind == "rest" ? "review530-row-rest-\(day.date ?? "")" : "review530-row-\(key)")
        } else if let id = item.sessionId {
            NavigationLink(value: TabRoute.plan529(.session(week: week, id: id))) {
                content(item, day: day)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(item.proposed == true ? "review530-row-proposed-\(key)" : "review530-row-\(key)")
        }
    }

    private func content(_ item: PFPlanWeekDoc.Item, day: PFPlanWeekDoc.Day) -> some View {
        let isRest = item.kind == "rest"
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if !isRest { Circle().fill(PFWeekColor529.effort(item.effort)).frame(width: 8, height: 8) }
                    Text(title(item))
                        .font(PFPlanFont543.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let line = small(item, day: day, isRest: isRest) { PFWeekSub529(text: line) }
                if let pill = item.changePill, !pill.isEmpty {
                    Text(hiding.text(pill))
                        .font(PFPlanFont543.text(12, weight: .medium))
                        .foregroundStyle(PFWeekColor529.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            Text(item.minutes.map { String($0) } ?? "\u{00B7}")
                .font(PFPlanFont543.text(14, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
        }
        .frame(minHeight: 44, alignment: .top)
        .contentShape(Rectangle())
    }

    private func title(_ item: PFPlanWeekDoc.Item) -> String {
        let base = item.title ?? (item.kind == "rest" ? "Rest" : "Workout")
        return item.optional == true ? "\(base) \u{00B7} optional" : base
    }

    /// "Proposed by the coach. First harder session of the week.", "Booked. ...", or for a rest day its tag and what to do.
    private func small(_ item: PFPlanWeekDoc.Item, day: PFPlanWeekDoc.Day, isRest: Bool) -> String? {
        if isRest {
            let parts = [day.tag, PFReviewFormat530.firstSentence(item.do ?? item.why)].compactMap { $0 }.filter { !$0.isEmpty }
            guard !parts.isEmpty else { return nil }
            let joined = parts.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }.joined(separator: ". ")
            return joined + "."
        }
        let lead = item.proposed == true ? "Proposed by the coach." : item.fixed == true ? "Booked." : nil
        let text = [lead, PFReviewFormat530.firstSentence(item.why)].compactMap { $0 }.joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}
