#if os(iOS)
import SwiftUI
import StrandDesign

// Compatibility shim for old Day-tab deep links and stored preferences. Sleep remains a first-level tab.

enum UnifiedDay {
    static let defaultsKey = "unifiedDay"

    /// Kept false so an old stored preference cannot hide Sleep behind the Day hub.
    static let isOn = false

    /// Kept as a no-op for the existing app-start call site.
    static func captureAtLaunch() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    /// The tab's title in the floating bar and the tab bar.
    static var tabTitle: LocalizedStringKey { isOn ? "Day" : "Sleep" }
    static var tabIcon: String { isOn ? "calendar" : "bed.double" }
}

#endif
