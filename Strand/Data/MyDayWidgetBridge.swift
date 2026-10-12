import Foundation
import StrandAnalytics

/// Lets the shared My Day screen hand today's timeline to a platform that publishes it (the iPhone
/// widget file) without the shared code knowing the widget exists. macOS leaves the hook unset.
enum MyDayWidgetBridge {
    @MainActor static var publisher: ((DayTimeline) -> Void)?

    @MainActor static func publish(_ timeline: DayTimeline) { publisher?(timeline) }
}
