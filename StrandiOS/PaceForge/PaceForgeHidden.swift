import SwiftUI
import StrandDesign

/// Settings > Hide numbers, as the PaceForge screens read it. Two switches (the daily scores; body weight and
/// body fat) say what is hidden; `PFPeek` is the one tap that shows everything again until the athlete leaves
/// the tab. Nothing stored changes: the screens only draw less.
final class PFPeek: ObservableObject {
    static let shared = PFPeek()
    @Published var isShowing = false
}

struct PFHiding: DynamicProperty {
    @AppStorage(HideScoresPrefs.scoresKey) private var scoresOn = false
    @AppStorage(HideScoresPrefs.bodyKey) private var bodyOn = false
    @ObservedObject private var peek = PFPeek.shared

    /// Whether either switch is on, whether or not the athlete is peeking.
    var isConfigured: Bool { scoresOn || bodyOn }

    func hides(_ kind: PFRedact.Kind) -> Bool {
        guard !peek.isShowing else { return false }
        return kind == .scores ? scoresOn : bodyOn
    }

    /// `text` with the hidden kinds' figures replaced; unchanged while nothing is hidden.
    func text(_ text: String) -> String {
        PFRedact.text(text, scores: hides(.scores), body: hides(.body))
    }

    /// `value`, or the placeholder while `kind` is hidden.
    func shown(_ value: String, _ kind: PFRedact.Kind) -> String {
        hides(kind) ? PFRedact.placeholder : value
    }
}

/// The one-tap reveal: a chip under the section picker while either switch is on.
struct PFRevealBar: View {
    private let hiding = PFHiding()
    @ObservedObject private var peek = PFPeek.shared

    var body: some View {
        if hiding.isConfigured {
            Button {
                peek.isShowing.toggle()
            } label: {
                Label(peek.isShowing ? "Numbers shown. Tap to hide them again" : "Some numbers are hidden. Tap to show",
                      systemImage: peek.isShowing ? "eye.slash" : "eye")
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pf-reveal")
        }
    }
}
