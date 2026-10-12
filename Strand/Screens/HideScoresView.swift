import SwiftUI
import StrandDesign

// MARK: - Hide scores (view side)
//
// The modifier that blanks a value under the two switches, and the Settings card that holds them. The keys and
// the rules are in HideScores.swift. A hidden value reads "Hidden" where it was; the screen it belongs to keeps
// its shape, and its accessibility label says it is hidden instead of reading the number out.

struct HiddenWhenPrivate: ViewModifier {
    let kind: HideScoresKind?
    let name: String
    @AppStorage(HideScoresPrefs.scoresKey) private var hideScores = false
    @AppStorage(HideScoresPrefs.bodyKey) private var hideBody = false

    private var isHidden: Bool {
        switch kind {
        case .scores?: return hideScores
        case .body?: return hideBody
        case nil: return false
        }
    }

    func body(content: Content) -> some View {
        if isHidden {
            content
                .hidden()
                .overlay {
                    Text(verbatim: HideScoresPrefs.placeholder)
                        .font(StrandFont.subhead.weight(.semibold))
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(name), hidden"))
                .accessibilityIdentifier("hidden-value")
        } else {
            content
        }
    }
}

extension View {
    /// Replaces this view's numbers with "Hidden" while the matching switch in Settings is on.
    func hiddenWhenPrivate(_ kind: HideScoresKind?, name: String) -> some View {
        modifier(HiddenWhenPrivate(kind: kind, name: name))
    }
}

/// Settings: the two switches.
struct HideScoresSettingsCard: View {
    @AppStorage(HideScoresPrefs.scoresKey) private var hideScores = false
    @AppStorage(HideScoresPrefs.bodyKey) private var hideBody = false

    var body: some View {
        StrandCard(padding: NoopMetrics.space5) {
            VStack(alignment: .leading, spacing: NoopMetrics.space4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Settings").strandOverline()
                    HStack(spacing: NoopMetrics.space2 + 2) {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(StrandPalette.accent)
                            .accessibilityHidden(true)
                        Text(verbatim: "Hide numbers")
                            .font(StrandFont.title2)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                }
                Text(verbatim: "For when someone else can see your screen. A hidden number reads \u{201C}Hidden\u{201D} on Today and in the PaceForge tab. Nothing stored changes.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $hideScores) {
                    Text(verbatim: "Hide Charge, Effort and Sleep numbers")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("hide-scores-toggle")
                Toggle(isOn: $hideBody) {
                    Text(verbatim: "Hide body weight and body fat")
                        .font(StrandFont.subhead)
                        .foregroundStyle(StrandPalette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(StrandPalette.accent)
                .accessibilityIdentifier("hide-body-toggle")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hide-numbers-card")
    }
}
