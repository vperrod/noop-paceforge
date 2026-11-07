import SwiftUI
import StrandDesign

// MARK: - My Day entry (Today)
//
// A one-line card under the Charge / Effort / Rest rings that opens My Day. It pushes a `TabRoute` value
// (not a closure destination) so a re-tap of the Today tab pops back to the root (#198). Today only: My
// Day for another date is reached from inside the screen with its day stepper.

struct MyDayEntryCard: View {
    var body: some View {
        NavigationLink(value: TabRoute.myDay) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.day.timeline.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MY DAY").font(StrandFont.overlineScaled(11)).tracking(1.0)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Sleep, workouts, plan and gaps in one timeline")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(NoopPanelSurface(tint: StrandPalette.accent, cornerRadius: 20))
        }
        .buttonStyle(LiquidPressStyle())
        .accessibilityLabel("My Day")
        .accessibilityHint("Opens the timeline of today")
        .accessibilityIdentifier("myday-entry")
    }
}
