import Foundation
import UserNotifications
#if os(iOS)
import BackgroundTasks
import UIKit
import WidgetKit
#endif

/// PRD-K5: a user-scheduled, local notification for the morning coaching brief. On iOS, the unified
/// Coach requires PaceForge and uses its server-written brief; it does not fall back to a separate
/// on-device Coach when PaceForge is disconnected. macOS uses the configured on-device Coach provider.
/// Tap → opens Coach with the full brief. Default OFF, like every NOOP automation.
///
/// Cross-platform (macOS + iOS), same architecture as `ScheduledDebugExport`:
/// - **macOS** — the app is usually running; a foreground `DispatchSourceTimer` fires at the chosen
///   minute, and `catchUpIfDue` covers the time having passed while the app wasn't open.
/// - **iOS** — a sideloaded, backgrounded app can't guarantee a wake at the exact minute. A
///   `BGAppRefreshTaskRequest` is submitted for *no earlier than* the chosen time; iOS decides when it
///   actually runs. If the slot is missed entirely (app never woken), the next foreground open's
///   `activateIfEnabled` catches up and generates then instead — same honest "best-effort" posture
///   `ScheduledDebugExport`'s Settings copy already uses.
///
/// Each platform uses its unified Coach source: PaceForge on iOS and the configured provider on macOS.
/// Generation additionally requires this feature's default-off `enabled` setting. A failed attempt never
/// marks the day "done", so the next wake retries instead of going permanently silent.
@MainActor
enum CoachBriefScheduler {

    // MARK: - Persisted settings (own keys; mirrors ScheduledDebugExport's shape)

    private enum K {
        static let enabled = "coachBrief.enabled"          // master enable; default OFF
        static let time = "coachBrief.timeMinutes"         // minutes since local midnight; default 07:00
        static let lastRun = "coachBrief.lastRunDayKey"    // yyyy-MM-dd of the last GENERATED brief (dedup)
        static let storedBrief = "coachBrief.storedText"   // the full brief, for the notification tap-through
        static let hasUnconsumed = "coachBrief.hasUnconsumedBrief"
        static let lastFailureReason = "coachBrief.lastFailureReason"
        static let lastFailureNotificationDay = "coachBrief.lastFailureNotificationDay"
        static let lastAttemptAt = "coachBrief.lastAttemptAt"
        static let lastSuccessAt = "coachBrief.lastSuccessAt"
        static let state = "coachBrief.state"
        static let lastTrigger = "coachBrief.lastTrigger"
        static let lastInvocation = "coachBrief.lastInvocation"
        static let lastInvocationAt = "coachBrief.lastInvocationAt"
        static let source = "coachBrief.source"
        static let dataReadiness = "coachBrief.dataReadiness"
        static let providerStatus = "coachBrief.providerStatus"
        static let lastResult = "coachBrief.lastResult"
        static let notificationOutcome = "coachBrief.notificationOutcome"
        static let backgroundEarliest = "coachBrief.backgroundEarliest"
        static let backgroundIssue = "coachBrief.backgroundIssue"
        // K10: the brief text mirrored into the App Group so the widget extension (separate process)
        // can read it. The app's own UserDefaults.standard isn't visible to the widget.
        static let widgetBriefKey = "coachBrief.widgetText"
        static let widgetBriefDateKey = "coachBrief.widgetDate"
    }

    /// 07:00 — a brief waiting when you check your phone (matches `ScheduledDebugExport`'s default).
    static let defaultTimeMinutes = 7 * 60
    /// The earliest a data-woken PaceForge brief may go out (04:00): a night's sleep cannot be in before then.
    static let earliestWakeMinutes = 4 * 60
    private static let minutesPerDay = 24 * 60

    /// Category id the posted notification carries, so `NotificationPresenter` can recognise a brief tap
    /// (as opposed to any other local notification) and route it to Coach.
    static let notificationCategoryId = "coach-brief"
    private static let requestIdPrefix = "coach-brief-"

    /// The Coach master switch, under the same `noop.` key Android writes and `RootTabView` binds.
    ///
    /// Read through `object(forKey:)` rather than `bool(forKey:)` because this pref defaults to TRUE and
    /// `bool(forKey:)` answers FALSE for a key that was never written. Taking the shorter spelling here
    /// would have disabled the Coach for every install that had never opened the toggle, which is exactly
    /// the population whose behaviour must not change.
    static var coachMasterEnabled: Bool {
        guard UserDefaults.standard.object(forKey: "noop.coachEnabled") != nil else { return true }
        return UserDefaults.standard.bool(forKey: "noop.coachEnabled")
    }

    /// Tear down whatever the brief has left lying around when the Coach master switch goes off.
    ///
    /// Gating `isEnabled` alone stops the NEXT brief being generated, which is the network half, but it
    /// leaves the LAST one on the wearer's home screen: the widget renders whatever was last published,
    /// so AI output would go on being displayed after the AI was switched off. Mirrors what
    /// `setEnabled(false)` already does for the brief's own flag, and what Android's `reschedule` does
    /// when it sees the master switch is off.
    ///
    /// Deliberately one-directional. Re-arming is not done here because this type is armed by
    /// `activateIfEnabled`, which `CoachView` calls when it appears -- a route that is reachable again the
    /// moment the switch goes back on, since the tab returns with it. Android re-arms on the flip instead,
    /// because there the brief is armed from app start rather than from the Coach screen.
    static func applyMasterSwitch(_ on: Bool) {
        guard !on else { return }
        cancel()
        // A brief already DELIVERED sits in Notification Centre until the wearer clears it, and tapping it
        // routes to Coach. Same leak as the widget, one surface over: AI output still on display, and in
        // this case still interactive, after the AI was switched off. Pending requests go too, so nothing
        // already queued can arrive afterwards.
        let centre = UNUserNotificationCenter.current()
        centre.getDeliveredNotifications { delivered in
            let ids = delivered.map(\.request.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            guard !ids.isEmpty else { return }
            centre.removeDeliveredNotifications(withIdentifiers: ids)
        }
        centre.getPendingNotificationRequests { pending in
            let ids = pending.map(\.identifier).filter { $0.hasPrefix(requestIdPrefix) }
            guard !ids.isEmpty else { return }
            centre.removePendingNotificationRequests(withIdentifiers: ids)
        }
        #if os(iOS)
        publishToWidget(nil)
        #endif
    }

    /// Whether the daily brief should run. Both gates, so the brief's own default-off flag keeps its
    /// meaning while the master switch can veto it outright.
    static var isEnabled: Bool { coachMasterEnabled && UserDefaults.standard.bool(forKey: K.enabled) }

    /// Time-of-day to generate, minutes since local midnight. Clamped to a valid minute. Default 07:00.
    static var timeMinutes: Int {
        let v = UserDefaults.standard.object(forKey: K.time) as? Int ?? defaultTimeMinutes
        return min(max(v, 0), minutesPerDay - 1)
    }

    /// The most recently generated full brief text (for the notification tap-through), or nil before the
    /// first successful generation.
    static var storedBrief: String? { UserDefaults.standard.string(forKey: K.storedBrief) }

    /// Short, non-sensitive reason from the last failed provider attempt. Kept locally so both the
    /// scheduled notification and the Settings retry button can explain what needs attention.
    static var lastFailureReason: String? { UserDefaults.standard.string(forKey: K.lastFailureReason) }

    /// Most recent safe-to-show state, such as waiting for overnight data or a brief ready.
    static var state: String? { UserDefaults.standard.string(forKey: K.state) }
    static var lastAttemptAt: Date? { UserDefaults.standard.object(forKey: K.lastAttemptAt) as? Date }
    static var lastSuccessAt: Date? { UserDefaults.standard.object(forKey: K.lastSuccessAt) as? Date }
    /// True when a brief was generated successfully today: `recordSuccess` stamps `lastSuccessAt` at the same moment
    /// it sets the "Today's brief is ready." state.
    static var hasBriefToday: Bool {
        guard let at = lastSuccessAt else { return false }
        return Calendar.current.isDateInToday(at)
    }

    /// iOS may defer an available background task, but a disabled/restricted setting explains why
    /// automatic catch-up cannot be expected. This is diagnostic context, not a delivery guarantee.
    static var backgroundRefreshAvailability: String {
        #if os(iOS)
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return "available; iOS still chooses whether and when to run"
        case .denied: return "disabled; iOS Settings or Low Power Mode may be responsible"
        case .restricted: return "restricted by iOS; the user cannot enable background refresh"
        @unknown default: return "unknown"
        }
        #else
        return "not applicable"
        #endif
    }

    /// Apple advises against warning for `.restricted`: the user cannot change that state.
    static var shouldExplainBackgroundRefreshUnavailable: Bool {
        #if os(iOS)
        UIApplication.shared.backgroundRefreshStatus == .denied
        #else
        false
        #endif
    }

    /// Copyable, privacy-safe diagnostics: no prompt, key, sensor values, or briefing text.
    static var diagnosticsSummary: String {
        let formatter = ISO8601DateFormatter()
        let attempt = lastAttemptAt.map(formatter.string(from:)) ?? "none"
        let success = lastSuccessAt.map(formatter.string(from:)) ?? "none"
        let reason = lastFailureReason ?? "none"
        let scheduledTime = String(format: "%02d:%02d", timeMinutes / 60, timeMinutes % 60)
        let stateText = state ?? "not recorded"
        let defaults = UserDefaults.standard
        let invocation = defaults.string(forKey: K.lastInvocation) ?? "not recorded"
        let invocationAt = (defaults.object(forKey: K.lastInvocationAt) as? Date).map(formatter.string(from:)) ?? "none"
        let trigger = defaults.string(forKey: K.lastTrigger) ?? "not recorded (no generation attempt yet)"
        let source = defaults.string(forKey: K.source) ?? "not recorded"
        let readiness = defaults.string(forKey: K.dataReadiness) ?? "not recorded"
        let provider = defaults.string(forKey: K.providerStatus) ?? "not recorded"
        let result = defaults.string(forKey: K.lastResult) ?? "not recorded"
        let notification = defaults.string(forKey: K.notificationOutcome) ?? "not recorded"
        let earliest = (defaults.object(forKey: K.backgroundEarliest) as? Date).map(formatter.string(from:)) ?? "not recorded"
        let backgroundIssue = defaults.string(forKey: K.backgroundIssue) ?? "none"
        let invocationNote = invocation == "not recorded"
            ? "No invocation was captured; this cannot establish why iOS did not run the app. Open Coach and tap Check now to try immediately."
            : ""
        return [
            "NOOP Coach brief diagnostics",
            "Selected source: \(source)",
            "Enabled: \(isEnabled)",
            "Scheduled local time: \(scheduledTime)",
            "State: \(stateText)",
            "Last app/scheduler invocation: \(invocation) at \(invocationAt)",
            invocationNote,
            "Last generation trigger: \(trigger)",
            "Data readiness: \(readiness)",
            "Provider/configuration: \(provider)",
            "Last result: \(result)",
            "Last attempt: \(attempt)",
            "Last success: \(success)",
            "Notification request: \(notification)",
            "iOS Background App Refresh: \(backgroundRefreshAvailability)",
            "Next background earliest run: \(earliest)",
            "Background scheduling issue: \(backgroundIssue)",
            "Last actionable issue: \(reason)"
        ].joined(separator: "\n")
    }

    private static func recordAttemptState(_ value: String, trigger: String) {
        recordInvocation(trigger)
        #if os(iOS)
        let source = "PaceForge shared Coach"
        let provider = "Server-owned Coach; no iPhone provider key used"
        #else
        let source = "Configured NOOP Coach provider"
        let provider = "Configured provider"
        #endif
        UserDefaults.standard.set(trigger, forKey: K.lastTrigger)
        UserDefaults.standard.set(source, forKey: K.source)
        UserDefaults.standard.set(provider, forKey: K.providerStatus)
        UserDefaults.standard.set("checking current brief and required data", forKey: K.dataReadiness)
        UserDefaults.standard.set("running", forKey: K.lastResult)
        UserDefaults.standard.set("not sent for this attempt yet", forKey: K.notificationOutcome)
        UserDefaults.standard.set(Date(), forKey: K.lastAttemptAt)
        UserDefaults.standard.set(value, forKey: K.state)
    }

    private static func recordInvocation(_ kind: String) {
        UserDefaults.standard.set(kind, forKey: K.lastInvocation)
        UserDefaults.standard.set(Date(), forKey: K.lastInvocationAt)
    }

    private static func recordBackgroundIssue(_ value: String?) {
        if let value { UserDefaults.standard.set(value, forKey: K.backgroundIssue) }
        else { UserDefaults.standard.removeObject(forKey: K.backgroundIssue) }
    }

    private static func recordDataReadiness(_ value: String) {
        UserDefaults.standard.set(value, forKey: K.dataReadiness)
    }

    private static func recordResult(_ value: String) {
        UserDefaults.standard.set(value, forKey: K.lastResult)
    }

    private static func recordSuccess(readiness: String = "ready") {
        let now = Date()
        UserDefaults.standard.set(now, forKey: K.lastSuccessAt)
        UserDefaults.standard.set("brief generated and stored", forKey: K.lastResult)
        UserDefaults.standard.set(readiness, forKey: K.dataReadiness)
        UserDefaults.standard.set("Today's brief is ready.", forKey: K.state)
    }

    static func recordFailureReason(_ reason: String?) {
        if let reason {
            UserDefaults.standard.set(reason, forKey: K.lastFailureReason)
        } else {
            UserDefaults.standard.removeObject(forKey: K.lastFailureReason)
        }
    }

    /// True when a generated brief hasn't yet been surfaced in the Coach transcript. Set right after a
    /// successful generation; cleared by `consumeStoredBrief()`.
    static var hasUnconsumedBrief: Bool { UserDefaults.standard.bool(forKey: K.hasUnconsumed) }

    /// Coach reads this once (on appear, with an empty transcript) to surface the stored brief as its
    /// first message without re-generating or re-sending anything. Returns nil (and leaves state
    /// untouched) when there's nothing unconsumed, so a normal open is unaffected.
    static func consumeStoredBrief() -> String? {
        guard hasUnconsumedBrief, let text = storedBrief else { return nil }
        UserDefaults.standard.set(false, forKey: K.hasUnconsumed)
        return text
    }

    // MARK: - K10: Widget-facing API (App Group, iOS only)

    #if os(iOS)
    /// Publish (or clear) the brief into the App Group so the widget extension can read it. Called
    /// from `catchUpIfDue` / `generateNow` after a successful generation, and from `setEnabled(false)`
    /// to clear the widget when the user turns the feature off.
    static func publishToWidget(_ text: String?) {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.suiteName) else { return }
        if let text {
            defaults.set(text, forKey: K.widgetBriefKey)
            defaults.set(Date(), forKey: K.widgetBriefDateKey)
        } else {
            defaults.removeObject(forKey: K.widgetBriefKey)
            defaults.removeObject(forKey: K.widgetBriefDateKey)
        }
        // Nudge WidgetKit to reload the coach-brief widget's timeline so it picks up the new text
        // without waiting for the next scheduled refresh. The kind string must match the widget's
        // `kind` property (see CoachBriefWidget.swift in StrandiOSWidgets).
        WidgetCenter.shared.reloadTimelines(ofKind: Self.widgetKind)
    }
    #endif

    /// The WidgetKit kind string for the coach-brief widget. Must match the `kind` property on
    /// `CoachBriefWidget` in `StrandiOSWidgets/`. Declared here so `publishToWidget` can reload
    /// timelines without importing the widget extension's type (the app target can't see it).
    static let widgetKind = "CoachBriefWidget"

    // MARK: - Enable / configure (Settings calls these)

    /// The result of enabling the schedule — mirrors `WindDownNudge.EnableOutcome` so the UI can revert
    /// the toggle and point at Settings on denial instead of persisting a dead "on" state.
    enum EnableOutcome { case scheduled, denied, off }

    /// Enable/disable and (re)schedule. Enabling gates on notification authorization first (asks once if
    /// undetermined; reports `.denied` rather than silently scheduling something the OS will never
    /// deliver). `completion` always runs on the main actor.
    static func setEnabled(_ on: Bool,
                            generateBrief: @escaping () async -> String?,
                            completion: (@MainActor (EnableOutcome) -> Void)? = nil) {
        guard on else {
            UserDefaults.standard.set(false, forKey: K.enabled)
            cancel()
            #if os(iOS)
            publishToWidget(nil)  // K10: clear the widget when the feature is turned off
            #endif
            completion?(.off)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            Task { @MainActor in
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    UserDefaults.standard.set(true, forKey: K.enabled)
                    scheduleNext(generateBrief: generateBrief)
                    completion?(.scheduled)
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        Task { @MainActor in
                            if granted {
                                UserDefaults.standard.set(true, forKey: K.enabled)
                                scheduleNext(generateBrief: generateBrief)
                                completion?(.scheduled)
                            } else {
                                UserDefaults.standard.set(false, forKey: K.enabled)
                                completion?(.denied)
                            }
                        }
                    }
                default:
                    UserDefaults.standard.set(false, forKey: K.enabled)
                    completion?(.denied)
                }
            }
        }
    }

    /// Update the time-of-day and reschedule so the new time takes effect immediately.
    static func setTimeMinutes(_ minutes: Int, generateBrief: @escaping () async -> String?) {
        UserDefaults.standard.set(min(max(minutes, 0), minutesPerDay - 1), forKey: K.time)
        if isEnabled { scheduleNext(generateBrief: generateBrief) }
    }

    /// Call whenever Coach (or its settings) appears so the schedule self-heals (re-arms the macOS timer
    /// after a relaunch, re-submits the iOS request) and a slot missed while the app wasn't open still
    /// generates once. No-op when the feature is off.
    static func activateIfEnabled(generateBrief: @escaping () async -> String?) {
        guard isEnabled else { return }
        scheduleNext(generateBrief: generateBrief)
        Task { await catchUpIfDue(generateBrief: generateBrief) }
    }

    /// The explicit "Generate now" button: always generates and stores, ignoring the once-per-day dedup,
    /// so a tap produces a fresh brief there and then. Does NOT post a notification (the user is already
    /// looking at Coach) and does NOT touch `lastRun`, so today's scheduled slot still fires normally.
    /// Returns the brief text, or nil on failure — the caller surfaces the recorded reason.
    @discardableResult
    static func generateNow(generateBrief: () async -> String?) async -> String? {
        recordInvocation("user_check")
        recordFailureReason(nil)
        recordAttemptState("Checking today's brief.", trigger: "user_check")
        let text: String?
        var readinessForSuccess = "configured Coach provider returned a brief"
        #if os(iOS)
        // Use the same source as the scheduled path so “Generate now” cannot produce a second, different
        // brief while PaceForge is the connected Coach source.
        switch await PaceForgeBriefSource.today(timeReached: true) {
        case .text(let paceForgeText, let readiness):
            text = paceForgeText
            readinessForSuccess = readiness
        case .notReady(let reason):
            recordDataReadiness("waiting: \(reason)")
            recordResult("waiting for data; no notification sent")
            UserDefaults.standard.set("not sent; waiting for data", forKey: K.notificationOutcome)
            UserDefaults.standard.set(reason, forKey: K.state)
            return nil
        case .unavailable(let reason):
            recordDataReadiness("PaceForge brief unavailable")
            UserDefaults.standard.set("PaceForge refresh or brief request failed", forKey: K.providerStatus)
            recordResult("failed; no notification sent")
            recordFailureReason(reason)
            UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            return nil
        case .notSetUp:
            let reason = "Connect NOOP to PaceForge to use the shared Coach for morning briefs."
            recordDataReadiness("not available: PaceForge is not connected")
            UserDefaults.standard.set("PaceForge connection not configured", forKey: K.providerStatus)
            recordResult("not configured; no notification sent")
            recordFailureReason(reason)
            UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            return nil
        }
        #else
        text = await generateBrief()
        #endif
        if text == nil {
            recordResult("failed; no notification sent")
            if lastFailureReason == nil {
                let reason = "The Coach provider did not return a brief."
                recordFailureReason(reason)
                UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            }
        } else {
            recordSuccess(readiness: readinessForSuccess)
            UserDefaults.standard.set("not sent; manual check", forKey: K.notificationOutcome)
        }
        return text
    }

    // MARK: - Due check + generation

    /// Whether a generation attempt is already running, so only one can be in flight at a time.
    ///
    /// `lastRun` is written only AFTER a successful generation, deliberately, so a failure retries at the
    /// next wake rather than marking the day done. That leaves the day guard open across a suspension:
    /// a caller reads `lastRun`, `await generateBrief()` suspends, and a second caller reaching the same
    /// guard still sees yesterday's value. Two call sites now arm the schedule (Coach's own `.task` and
    /// the scene-phase entry), so a cold launch straight onto the Coach tab could run two generations at
    /// once, paying for two provider calls and posting two brief notifications for the same day.
    ///
    /// Claiming is what makes the day guard hold across that await. MainActor-isolated because the two
    /// callers arrive on different executors: `activateIfEnabled` starts an unstructured `Task` with no
    /// isolation, while the BGTask handler runs its worker on the MainActor.
    @MainActor private static var generationInFlight = false

    /// Take the single generation slot, or report that another attempt already holds it.
    @MainActor private static func claimGeneration() -> Bool {
        guard !generationInFlight else { return false }
        generationInFlight = true
        return true
    }

    /// Give the generation slot back. Always called immediately after the attempt, before either outcome
    /// is branched on, so a failed generation releases it exactly like a successful one.
    @MainActor private static func releaseGeneration() { generationInFlight = false }

    /// If today's brief is due (we're at/after the chosen time and haven't generated today), generate it
    /// once: store the text, mark today done, and post the notification. Covers macOS launches where the
    /// time passed while the app wasn't open, and the iOS foreground/BGTask paths.
    ///
    /// Returns whether this call can be considered successful: `true` when there was nothing to do
    /// (feature off, not yet time, or already ran today) or generation succeeded; `false` only when
    /// generation was attempted and failed (so the iOS BGTask handler can report the real outcome and
    /// retry on the next wake instead of marking the day done on a failure).
    @discardableResult
    static func catchUpIfDue(generateBrief: () async -> String?, trigger: String = "foreground_catch_up") async -> Bool {
        recordInvocation(trigger)
        guard isEnabled else { return true }
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let timeReached = nowMinutes >= timeMinutes
        #if os(iOS)
        // With PaceForge the brief is woken by data, not by the clock: from the earliest wake time on, it goes out as soon as the
        // night's sleep and HRV are in. The chosen time is only the latest it waits.
        guard timeReached || nowMinutes >= earliestWakeMinutes else { return true }
        #else
        guard timeReached else { return true }                                                // not yet time today
        #endif
        guard UserDefaults.standard.string(forKey: K.lastRun) != dayKey(now) else { return true } // already ran today

        // One attempt at a time; see `generationInFlight` for why the day guard alone is not enough.
        guard await claimGeneration() else { return true }
        recordFailureReason(nil)
        recordAttemptState("Checking today's brief.", trigger: trigger)
        let generated: String?
        var readinessForSuccess = "configured Coach provider returned a brief"
        #if os(iOS)
        // With PaceForge connected the brief is PaceForge's own (written on the server, no AI key needed here). Not published yet
        // means wait for the next wake quietly: the key-based path would only post "unavailable".
        switch await PaceForgeBriefSource.today(timeReached: timeReached) {
        case .text(let text, let readiness):
            generated = text
            readinessForSuccess = readiness
        case .notReady(let reason):
            recordDataReadiness("waiting: \(reason)")
            recordResult("waiting for data; no notification sent")
            UserDefaults.standard.set("not sent; waiting for data", forKey: K.notificationOutcome)
            UserDefaults.standard.set(reason, forKey: K.state)
            await releaseGeneration()
            return true
        case .unavailable(let reason):
            recordDataReadiness("PaceForge brief unavailable")
            UserDefaults.standard.set("PaceForge refresh or brief request failed", forKey: K.providerStatus)
            recordFailureReason(reason)
            // A transient PaceForge outage during iOS's earliest background window is not yet
            // a missed morning brief. Keep the actionable reason in Settings, retry on the next
            // wake, and wait until the athlete's configured latest time before raising an alert.
            if !timeReached {
                recordResult("retrying before selected latest time")
                UserDefaults.standard.set("not sent; retrying before selected latest time", forKey: K.notificationOutcome)
                UserDefaults.standard.set("PaceForge is unavailable; retrying before the scheduled time. \(reason)",
                                          forKey: K.state)
                await releaseGeneration()
                return true
            }
            recordResult("failed; retry scheduled")
            UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            generated = nil
        case .notSetUp:
            recordDataReadiness("not available: PaceForge is not connected")
            UserDefaults.standard.set("PaceForge connection not configured", forKey: K.providerStatus)
            guard timeReached else {            // Wait until the selected latest time before reporting missing PaceForge setup.
                recordResult("waiting for selected latest time")
                UserDefaults.standard.set("not sent; waiting for selected latest time", forKey: K.notificationOutcome)
                UserDefaults.standard.set(
                    String(localized: "Waiting until the selected brief time: connect NOOP to PaceForge for the shared Coach."),
                    forKey: K.state)
                await releaseGeneration()
                return true
            }
            let reason = "Connect NOOP to PaceForge to use the shared Coach for morning briefs."
            recordResult("not configured; retry scheduled")
            recordFailureReason(reason)
            UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            generated = nil
        }
        #else
        generated = await generateBrief()
        #endif
        await releaseGeneration()

        guard let text = generated else {
            recordResult("failed; retry scheduled")
            if lastFailureReason == nil {
                let reason = "The Coach provider did not return a brief."
                recordFailureReason(reason)
                UserDefaults.standard.set("Action needed — open Brief settings for the reason and next step.", forKey: K.state)
            }
            // No brief arrived from the platform's Coach source. Never mark the day done, so the next
            // wake (BGTask retry, or the next foreground open) tries again. iOS can wake this path
            // repeatedly in one day, so notify once per local day; keep lastFailureReason current for
            // Coach Settings, where the athlete can see what needs fixing.
            let today = dayKey(now)
            if UserDefaults.standard.string(forKey: K.lastFailureNotificationDay) != today {
                UserDefaults.standard.set(today, forKey: K.lastFailureNotificationDay)
                postNotification(title: String(localized: "Coach brief unavailable"),
                                  body: failureNotificationBody,
                                  isRetry: true)
            } else {
                UserDefaults.standard.set("not sent; already alerted today", forKey: K.notificationOutcome)
            }
            return false
        }

        recordFailureReason(nil)
        recordSuccess(readiness: readinessForSuccess)
        UserDefaults.standard.set(dayKey(now), forKey: K.lastRun)
        UserDefaults.standard.set(text, forKey: K.storedBrief)
        UserDefaults.standard.set(true, forKey: K.hasUnconsumed)
        #if os(iOS)
        publishToWidget(text)  // K10: mirror into the App Group for the widget
        #endif
        postNotification(title: String(localized: "Today's coaching brief"),
                          body: oneLineSummary(from: text))
        return true
    }

    /// Pure: the notification body is the brief's first non-empty line, trimmed and length-capped so it
    /// fits a notification banner. Unit-testable without any I/O.
    static func oneLineSummary(from brief: String, maxLength: Int = 120) -> String {
        let firstLine = brief
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? brief
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxLength else { return trimmed }
        let cut = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return trimmed[..<cut].trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func postNotification(title: String, body: String, isRetry: Bool = false) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = notificationCategoryId
        // Immediate delivery (trigger nil) — this fires when generation completes, not at a
        // pre-scheduled fixed-content time like `WindDownNudge`. Separate retry and success IDs let a
        // brief that recovers later the same day still announce success.
        let kind = isRetry ? "retry" : "success"
        let request = UNNotificationRequest(identifier: requestIdPrefix + kind + "-" + dayKey(Date()),
                                            content: content, trigger: nil)
        UserDefaults.standard.set("submitting request to Notification Centre", forKey: K.notificationOutcome)
        UNUserNotificationCenter.current().add(request) { error in
            let outcome = error.map { "request failed: \($0.localizedDescription)" }
                ?? "request accepted; delivery is controlled by iOS notification settings"
            UserDefaults.standard.set(outcome, forKey: K.notificationOutcome)
        }
    }

    private static var failureNotificationBody: String {
        let detail = lastFailureReason ?? "The provider did not return a brief."
        // Keep the useful error category (for example, "PaceForge: HTTP 503") on the
        // lock screen, but never disclose the athlete's configured private server host.
        let reason = SelfHostedPushClient.paceForgeHost.map {
            detail.replacingOccurrences(of: $0, with: "PaceForge")
        } ?? detail
        return "Today's brief couldn't be generated: \(reason) Open Coach to fix it or retry."
    }

    /// yyyy-MM-dd local-day key for the once-per-day dedup. POSIX locale so the key is stable everywhere.
    private static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Seconds from now until the next wall-clock occurrence of `minuteOfDay` (today if still ahead, else
    /// tomorrow). Mirrors `ScheduledDebugExport.secondsToNextOccurrence`.
    private static func secondsToNextOccurrence(_ minuteOfDay: Int, now: Date = Date()) -> TimeInterval {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        comps.second = 0
        var target = cal.date(from: comps) ?? now
        if target <= now { target = cal.date(byAdding: .day, value: 1, to: target) ?? target }
        return max(1, target.timeIntervalSince(now))
    }

    // MARK: - Scheduling

    private static var macTimer: DispatchSourceTimer?

    /// (Re)arm the next occurrence. macOS uses a foreground `DispatchSourceTimer`; iOS submits a
    /// background-refresh request. Both target the next wall-clock occurrence of `timeMinutes`.
    private static func scheduleNext(generateBrief: @escaping () async -> String?) {
        #if os(macOS)
        macTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let delay = secondsToNextOccurrence(timeMinutes)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler {
            Task { @MainActor in
                guard isEnabled else { return }
                _ = await catchUpIfDue(generateBrief: generateBrief, trigger: "scheduled_timer")
                scheduleNext(generateBrief: generateBrief)
            }
        }
        timer.resume()
        macTimer = timer
        #elseif os(iOS)
        submitBackgroundRequest()
        #endif
    }

    /// Cancel any armed schedule.
    private static func cancel() {
        #if os(macOS)
        macTimer?.cancel()
        macTimer = nil
        #elseif os(iOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: bgTaskIdentifier)
        UserDefaults.standard.removeObject(forKey: K.backgroundEarliest)
        #endif
    }

    // MARK: - iOS background task plumbing

    #if os(iOS)
    /// iOS BGTask identifier, derived from the running bundle id so it tracks `BUNDLE_ID_PREFIX` and
    /// matches the iOS target's `BGTaskSchedulerPermittedIdentifiers` (Info.plist / project.yml).
    static let bgTaskIdentifier = (Bundle.main.bundleIdentifier ?? "com.noopapp.noop") + ".coachbrief"
    private static var logBackgroundFailure: ((String) -> Void)?

    /// Register the BGTask handler. MUST be called from the app's launch (before launch finishes) — call
    /// this from `StrandiOSApp.init()` with the app-owned Coach and strap log.
    static func register(generateBrief: @escaping () async -> String?, log: @escaping (String) -> Void) {
        logBackgroundFailure = log
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            Task { @MainActor in recordInvocation("background_refresh") }
            let completion = TaskCompletionGuard(task: task)
            let worker = Task { @MainActor in
                guard isEnabled else {
                    completion.finish(success: true)
                    return
                }
                let succeeded = await catchUpIfDue(generateBrief: generateBrief, trigger: "background_refresh")
                // Single-shot; request the next occurrence regardless of this run's outcome so a failed
                // generation still retries at the next wake rather than going silent for good.
                submitBackgroundRequest()
                completion.finish(success: succeeded)
            }
            task.expirationHandler = {
                worker.cancel()
                Task { @MainActor in
                    recordResult("background task expired before completion")
                    UserDefaults.standard.set("background task expired", forKey: K.backgroundIssue)
                }
                completion.finish(success: false)
            }
        }
    }

    /// `BGTask` completion is single-shot even when the normal path races expiration.
    private final class TaskCompletionGuard: @unchecked Sendable {
        private let task: BGTask
        private let lock = NSLock()
        private var finished = false

        init(task: BGTask) { self.task = task }

        func finish(success: Bool) {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return }
            finished = true
            task.setTaskCompleted(success: success)
            task.expirationHandler = nil
        }
    }

    /// Submit a background-refresh request for *no earlier than* the next chosen time. iOS decides when
    /// (and whether) to actually run it — best-effort, same honesty as `ScheduledDebugExport`.
    /// Until today's brief is out, ask again every 15 minutes (iOS decides when it really runs; opening the app also tries).
    /// Once it is out, the next attempt is tomorrow's earliest wake time.
    private static func secondsToNextBriefAttempt() -> TimeInterval {
        let now = Date()
        let cal = Calendar.current
        guard UserDefaults.standard.string(forKey: K.lastRun) == dayKey(now),
              let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)),
              let wake = cal.date(byAdding: .minute, value: earliestWakeMinutes, to: tomorrow) else { return 15 * 60 }
        return max(60, wake.timeIntervalSince(now))
    }

    private static func submitBackgroundRequest() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: secondsToNextBriefAttempt())
        do {
            try BGTaskScheduler.shared.submit(request)
            if let earliest = request.earliestBeginDate {
                UserDefaults.standard.set(earliest, forKey: K.backgroundEarliest)
            } else {
                UserDefaults.standard.removeObject(forKey: K.backgroundEarliest)
            }
            recordBackgroundIssue(nil)
        } catch {
            recordBackgroundIssue(error.localizedDescription)
            logBackgroundFailure?("coach brief: background request refused (\(error.localizedDescription))")
        }
    }
    #endif
}
