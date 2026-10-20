#if os(iOS)
import SwiftUI
import StrandDesign

// The opt-in "New Day tab (beta)". Off by default: with the switch off the tab bar and every screen are the ones build 479 has
// (tab 2 is Sleep). On, tab 2 is labelled Day and hosts My Day, Sleep, Recovery, Activity and Health as chips (DayHostView). The
// switch is read once, at launch, so a change applies after the app is restarted.

enum UnifiedDay {
    static let defaultsKey = "unifiedDay"

    /// Read once per launch; the Settings switch only writes the preference.
    static let isOn: Bool = UserDefaults.standard.bool(forKey: defaultsKey)

    /// Called from the app's init so the value is the one the app started with, however late a screen first asks. A launch always
    /// opens the Day tab on its Sleep chip (the screen the tab replaces), never on a chip remembered from a previous run.
    static func captureAtLaunch() {
        guard isOn else { return }
        UserDefaults.standard.set(DayChip.sleep.rawValue, forKey: DayChip.storageKey)
        NoopDiag.crumb("day.unified enabled")
    }

    /// The tab's title in the floating bar and the tab bar.
    static var tabTitle: LocalizedStringKey { isOn ? "Day" : "Sleep" }
    static var tabIcon: String { isOn ? "calendar" : "bed.double" }
}

/// Settings > Tools > New Day tab (beta).
struct UnifiedDayToggle: View {
    @AppStorage(UnifiedDay.defaultsKey) private var isEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Text("New Day tab (beta)")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(StrandPalette.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-tool-unifiedday")
            Text("Replaces the Sleep tab by a Day tab: My Day, Sleep, Recovery, Activity and Health in one place. Off keeps the tabs you have today. Restart NOOP to apply a change.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
