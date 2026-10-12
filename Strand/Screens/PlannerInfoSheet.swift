import SwiftUI
import StrandDesign

// MARK: - "How it works" sheet for the Effort target and the Sleep Planner
//
// The same layout MetricHowItWorks uses (fixed header with a close button, NoopCard sections, "Got it"
// footer), driven by plain data so the Effort target and the Sleep Planner can each carry their own copy
// and the formulas they print come from the constants in StrandAnalytics rather than being retyped.

struct PlannerInfoSection: Identifiable {
    let heading: String
    let body: String
    var id: String { heading }
}

struct PlannerInfoSheet: View {
    let title: String
    let tint: Color
    let sections: [PlannerInfoSection]
    /// Shown in its own card above the sections while a figure is still calibrating.
    var calibration: String?
    let identifier: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header.background(NoopChromeSurface())
            Divider().overlay(StrandPalette.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: NoopMetrics.sectionGap) {
                    if let calibration { calibrationCard(calibration) }
                    ForEach(sections) { section in card(section) }
                }
                .padding(20)
            }
            Divider().overlay(StrandPalette.hairline)
            footerBar
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noopSheetPresentation(largeFirst: false)
        #endif
        .background(StrandPalette.surfaceBase)
        .accessibilityIdentifier(identifier)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOW IT WORKS").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(verbatim: title).font(StrandFont.rounded(26, weight: .bold))
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(20)
    }

    private func card(_ section: PlannerInfoSection) -> some View {
        NoopCard(tint: tint) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: section.heading).font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                Text(verbatim: section.body).font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func calibrationCard(_ line: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("CALIBRATING").font(StrandFont.overline)
                    .tracking(StrandFont.overlineTracking)
                    .foregroundStyle(StrandPalette.textTertiary)
                Text(verbatim: line).font(StrandFont.subhead.weight(.semibold))
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("planner-calibration")
    }

    private var footerBar: some View {
        HStack {
            AskCoachButton(metric: title, onClose: onClose)
            Spacer()
            Button(action: onClose) {
                Text("Got it").frame(minWidth: 120).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(StrandPalette.accent)
        }
        .padding(16)
    }
}

/// A small ⓘ that opens a `PlannerInfoSheet`. Owns its presentation state, like `MetricInfoButton`.
struct PlannerInfoButton: View {
    let title: String
    let tint: Color
    let sections: [PlannerInfoSection]
    var calibration: String?
    let identifier: String
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(StrandPalette.textTertiary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "How \(title) works"))
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $isShowing) {
            PlannerInfoSheet(title: title, tint: tint, sections: sections, calibration: calibration,
                             identifier: "\(identifier)-sheet", onClose: { isShowing = false })
        }
    }
}
