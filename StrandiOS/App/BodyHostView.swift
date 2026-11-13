#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Health > Body
//
// PaceForge's Body screen (the Hume scale: trend, score, composition, goals, readings) under a row to the Lab Book. Both are the screens
// that exist today, unchanged; this is the content of the Body chip of the Health tab.

/// The Body chip of Health: the Lab Book row, then the scale screen.
struct HealthBodyChip: View {
    var body: some View {
        VStack(alignment: .leading, spacing: NoopMetrics.sectionSpacing) {
            IndexSection("Lab") {
                IndexRow("Lab Book", "cross.case.fill", MoreDestination.labBook, id: "health-body-labbook")
            }
            BodyPaceForgeChip()
        }
        .containerIdentifier("health-chip-content-body")
    }
}

private struct BodyPaceForgeChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(BodyPaceForgeContent(snapshot: snapshot)) })
            .containerIdentifier("body-chip-content-body")
    }
}

/// The Body screen, or its placeholder while Settings > Hide numbers hides body weight and body fat.
private struct BodyPaceForgeContent: View {
    let snapshot: PFSnapshot
    private let hiding = PFHiding()

    var body: some View {
        if hiding.hides(.body) {
            PFBodyHiddenView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                PFPageNote(key: "body")
                PFBodyView(snapshot: snapshot)
            }
        }
    }
}
#endif
