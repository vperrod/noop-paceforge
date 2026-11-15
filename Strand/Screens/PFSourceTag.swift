import SwiftUI
import StrandDesign

// Lives in the shared target because Today (shared with macOS) draws it beside vitals; the PaceForge screens on iPhone use it too.

/// A source label next to a figure: "NOOP", "GARMIN", "PACEFORGE". Never blended into one number.
struct PFSourceTag: View {
    let source: String?

    var body: some View {
        if let source, !source.isEmpty {
            Text(source == "NOOP" ? "NOOP STRAP" : source.uppercased())
                .lookCaps(9.5)
                .foregroundStyle(NoopLook.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(NoopLook.row))
                .accessibilityLabel("Source \(source)")
        }
    }
}
