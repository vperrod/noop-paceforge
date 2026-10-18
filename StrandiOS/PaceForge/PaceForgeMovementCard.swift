import SwiftUI
import StrandDesign

// "Daily movement" on PaceForge Today: today's Garmin steps against the athlete's own usual range, the Garmin intensity minutes and
// the last seven days, read from movement.json. Steps are a separate, labelled signal and the card ends on the server's rule for
// what they do and do not feed. A file that is not served leaves the card out; an item that is unavailable shows the server's reason.

@MainActor
final class PFMovementStore: ObservableObject {
    static let shared = PFMovementStore()

    @Published private(set) var state: PFDocState<PFMovement> = .missing
    private var lastFetch: Date?

    private init() {}

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 120 { return }
        guard PFAPI.isConfigured else { return }
        let data = await Self.read(PFMovementParse.path)
        state = PFMovementParse.document(PFJ(data: data))
        lastFetch = Date()
    }

    /// The server's copy, else (offline) the one the last good fetch left on the phone. A fixture never reads the cache.
    nonisolated private static func read(_ path: String) async -> Data? {
        let data = await PFAPI.fetchOptional(path)
        if data == nil, PFAPI.usesPhoneState { return PFStore.read(path: path) }
        return data
    }
}

struct PFMovementCard: View {
    @ObservedObject private var store = PFMovementStore.shared

    var body: some View {
        Group {
            switch store.state {
            case .ready(let movement, _):
                PFMovementBody(movement: movement)
            case .unavailable(let reason, _):
                PFIntelNote(title: "Daily movement", icon: "figure.walk",
                            text: reason ?? "PaceForge has not published today's movement yet.",
                            identifier: "pf-movement-unavailable")
            case .missing:
                EmptyView()
            }
        }
        .task { await store.refreshIfStale() }
    }
}

struct PFMovementBody: View {
    let movement: PFMovement

    private var chipColor: Color {
        switch movement.position {
        case "low": return NoopLook.trendDown
        case "high": return NoopLook.trendUp
        case "typical": return NoopLook.rest
        default: return NoopLook.textTertiary
        }
    }

    var body: some View {
        PFCard(title: "Daily movement", icon: "figure.walk",
               trailing: { PFChip(text: PFMovementLogic.chipText(movement), color: chipColor) }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(PFMovementLogic.countText(movement.stepsToday))
                        .font(LookFont.numeral(44))
                        .foregroundStyle(NoopLook.textPrimary)
                        .accessibilityIdentifier("pf-movement-steps")
                    Text("steps \(PFMovementLogic.whenText(movement))")
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                if let usual = PFMovementLogic.usualText(movement) {
                    Text(usual)
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                }
                rangeBar
                if movement.series.count > 1 { weekBars }
                if let line = PFMovementLogic.intensityText(movement) {
                    Text(line)
                        .font(LookFont.text(13, weight: .medium))
                        .foregroundStyle(NoopLook.textSecondary)
                        .accessibilityIdentifier("pf-movement-intensity")
                }
                PFParagraph(PFMovementLogic.whatCounts)
            }
        }
        .containerIdentifier("pf-movement")
    }

    @ViewBuilder private var rangeBar: some View {
        if let bar = PFMovementLogic.rangeBar(movement) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(NoopLook.track)
                    Capsule()
                        .fill(NoopLook.rest.opacity(0.45))
                        .frame(width: max(width * CGFloat(bar.high - bar.low), 4))
                        .offset(x: width * CGFloat(bar.low))
                    Circle()
                        .fill(NoopLook.textPrimary)
                        .frame(width: 12, height: 12)
                        .offset(x: min(max(width * CGFloat(bar.today) - 6, 0), width - 12))
                }
            }
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today against your usual range")
            .accessibilityValue(PFMovementLogic.usualText(movement) ?? "")
            .accessibilityIdentifier("pf-movement-range")
        }
    }

    private var weekBars: some View {
        let fractions = PFMovementLogic.weekFractions(movement.series)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(movement.series.enumerated()), id: \.element.id) { index, day in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Color.clear.frame(height: 44)
                        if let fraction = fractions[index] {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.date == movement.asOf ? NoopLook.textPrimary : NoopLook.rest.opacity(0.6))
                                .frame(height: 44 * CGFloat(fraction))
                        } else {
                            Circle().fill(NoopLook.textMuted).frame(width: 4, height: 4)
                        }
                    }
                    Text(day.weekdayLetter)
                        .font(LookFont.text(11, weight: .medium))
                        .foregroundStyle(NoopLook.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.weekdayName)
                .accessibilityValue(day.steps.map { "\(PFMovementLogic.countText($0)) steps" } ?? "no count")
            }
        }
        .containerIdentifier("pf-movement-week")
    }
}
