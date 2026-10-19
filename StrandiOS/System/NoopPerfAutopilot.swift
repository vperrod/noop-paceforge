#if DEBUG && os(iOS)
import SwiftUI
import UIKit

extension Notification.Name {
    /// DEBUG: the perf autopilot asks the shell for a tab (object: the tab's index).
    static let noopPerfSelectTab = Notification.Name("noop.perf.selectTab")
}

/// DEBUG `-NoopPerfAutopilot`: the app walks its own screens for the perf test, so nothing queries the accessibility tree
/// while a screen is measured (an XCUITest query makes SwiftUI build that tree and resolve every Text on the main thread,
/// which a phone without an assistive feature never does). Each step names its screen (NoopDiag.screen through the shell
/// and the PaceForge tab), waits for it to load, scrolls its scroll view to the end and back, then rests. The probe says
/// "autopilot":"done" at the end; the test reads it once.
enum NoopPerfAutopilot {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-NoopPerfAutopilot") }
    private(set) static var isDone = false

    /// Seconds the whole walk takes, so the test knows how long to wait before it reads the probe.
    static let settleSeconds: UInt64 = 25

    @MainActor
    static func startIfRequested() {
        guard isRequested else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: settleSeconds * 1_000_000_000)
            await visitTab(1)                           // Trends
            await visitTab(0)                           // Today, second visit (the first carried the launch)
            UserDefaults.standard.set("today", forKey: "noop.paceforge.segment")
            await visitTab(3, settle: 6)                // PaceForge Today, first open: load and build
            for segment in ["coach", "week", "insights", "body"] {
                UserDefaults.standard.set(segment, forKey: "noop.paceforge.segment")
                await walk(settle: 3)
            }
            NoopDiag.screen("perf.done")
            isDone = true
        }
    }

    @MainActor
    private static func visitTab(_ index: Int, settle: Double = 3) async {
        NotificationCenter.default.post(name: .noopPerfSelectTab, object: index)
        await walk(settle: settle)
    }

    /// Waits for the screen, scrolls it to the end and back in small steps (each one a layout of the content), then rests.
    @MainActor
    private static func walk(settle: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
        if let scroll = mainScrollView() {
            let maxY = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let steps = 24
            for i in Array(1...steps) + Array((0..<steps).reversed()) {
                scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top + maxY * CGFloat(i) / CGFloat(steps)),
                                        animated: false)
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
    }

    /// The tallest visible vertical scroll view of the key window: the screen's content.
    @MainActor
    private static func mainScrollView() -> UIScrollView? {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        guard let window else { return nil }
        var best: UIScrollView?
        var stack: [UIView] = [window]
        while let view = stack.popLast() {
            if let scroll = view as? UIScrollView, scroll.window != nil, !scroll.isHidden, scroll.alpha > 0.01,
               scroll.bounds.height > window.bounds.height * 0.5,
               window.bounds.intersects(scroll.convert(scroll.bounds, to: window)),
               scroll.contentSize.height > scroll.bounds.height,
               scroll.contentSize.height > (best?.contentSize.height ?? 0) {
                best = scroll
            }
            stack.append(contentsOf: view.subviews)
        }
        return best
    }
}
#endif
