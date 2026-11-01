#if os(iOS)
import SwiftUI
import StrandDesign

// Active hours (see PaceForgeBandBatchD.swift for the numbers): in how many different clock hours of the day the athlete took at least 250
// steps, against their own usual. Garmin's steps; context only, because steps never feed Effort, Strain or readiness. One line and a gloss,
// on the Insights load cards and at the bottom of the Daily movement card.

/// The line, its status and the gloss. No card of its own, so the movement card can hold it.
struct PFActiveHoursLine: View {
    let hours: PFActiveHours
    private let hiding = PFHiding()

    private var statusWord: String? { PFBatchDLogic.activeStatusWord(hours.status) }

    /// The server's sentence once it can compare; the plain count until then.
    private var sentence: String {
        hours.line ?? "Active in \(hours.activeHours) different hours of the day"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Active hours").lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                if let statusWord { PFChip(text: statusWord, color: PFColor.sky) }
            }
            PFParagraph(sentence)
            if let gloss = hours.gloss {
                Text(hiding.text(gloss))
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let source = hours.source {
                Text(hiding.text(source)).font(LookFont.text(11, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-active-hours")
    }
}

struct PFActiveHoursCard: View {
    let hours: PFActiveHours

    var body: some View {
        PFCard("Active hours", icon: "figure.walk") {
            PFActiveHoursLine(hours: hours)
        }
        .containerIdentifier("pf-active-hours-card")
    }
}

/// Inside the Daily movement card: nothing until the store has the document.
struct PFActiveHoursInline: View {
    @ObservedObject private var store = PFBatchDStore.shared

    var body: some View {
        if let hours = store.activeHours {
            PFActiveHoursLine(hours: hours)
        }
    }
}
#endif
