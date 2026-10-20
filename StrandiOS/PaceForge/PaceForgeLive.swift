import SwiftUI

/// Fetches PaceForge's JSON with the sync client's endpoint and Keychain token.
/// UI tests run without a server: `-PaceForgeFixture` serves the files from `PF_FIXTURE_JSON` instead.
enum PFAPI {
    /// Path (relative to the PaceForge root) -> JSON value or markdown text, for the UI-test fixture.
    static let fixture: [String: Any]? = {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-PaceForgeFixture") else { return nil }
        let environment = ProcessInfo.processInfo.environment
        let data: Data?
        if let packed = environment["PF_FIXTURE_DEFLATE"] {
            // A real-size fixture (the perf tests) is too big for one launch variable as text: base64 of raw DEFLATE.
            data = Data(base64Encoded: packed).flatMap { try? ($0 as NSData).decompressed(using: .zlib) as Data }
        } else {
            data = environment["PF_FIXTURE_JSON"]?.data(using: .utf8)
        }
        guard let data, let files = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return files
        #else
        return nil
        #endif
    }()

    static var isFixture: Bool { fixture != nil }

    /// Whether the saved copies on the phone (the last good documents, the Today arrangement, the hidden cards, the Healthspan
    /// weeks) are in play. They always are on a real run; a fixture run ignores them so every UI test starts clean, unless a UI
    /// test asks to start from saved state (`PFSavedStateSeed`).
    static var usesPhoneState: Bool { !isFixture || PFSavedStateSeed.isRequested }

    /// DEBUG UI-test switch that shows the widget gallery in place of the PaceForge screens.
    static var showsWidgetGallery: Bool {
        #if DEBUG
        return isFixture && ProcessInfo.processInfo.arguments.contains("-PaceForgeWidgetGallery")
        #else
        return false
        #endif
    }

    /// The phone's today, or the fixed day a UI-test fixture is written for.
    static var todayISO: String {
        #if DEBUG
        if let day = fixture?["today"] as? String { return day }
        #endif
        return PFFormat.isoString(Date())
    }

    /// UI-test switches that swap one fixture file for its alternative, so a screen's second state can be
    /// captured: `-PaceForgeBehaviourInsufficient` serves a behaviour list with no qualifying question, and so on.
    #if DEBUG
    private static let fixtureVariants: [(flag: String, path: String, alternate: String)] = [
        ("-PaceForgeBehaviourInsufficient", "data/behaviour-impact.json", "data/behaviour-impact.insufficient.json"),
        // Race week on (the default fixture is outside race week, so the plain countdown still shows).
        ("-PaceForgeRaceWeek", "data/race-week.json", "data/race-week.active.json"),
        ("-PaceForgeSimsEmpty", "data/hyrox-sim-analysis.json", "data/hyrox-sim-analysis.empty.json"),
        ("-PaceForgeSimsEmpty", "data/hyrox-sims.json", "data/hyrox-sims.empty.json"),
        ("-PaceForgeEasyPending", "data/easy-mode.json", "data/easy-mode.pending.json"),
        ("-PaceForgeEasyIdle", "data/easy-mode.json", "data/easy-mode.idle.json"),
        ("-PaceForgeMuscleCalibrating", "data/muscle-check.json", "data/muscle-check.calibrating.json"),
        // "Where you stand" with sex and age missing: the not-applicable state.
        ("-PaceForgeStandingNotApplicable", "data/standing.json", "data/standing.na.json"),
        // No ride-metrics.json at all (rides hidden), and a ride whose stream file is missing (no chart).
        ("-PaceForgeRideNone", "data/ride-metrics.json", "data/ride-metrics.missing.json"),
        // A card hidden in PaceForge itself (dismissed.json), united with the ones hidden on the phone.
        ("-PaceForgeServerDismissed", "data/dismissed.json", "data/dismissed.server.json"),
        ("-PaceForgeRideNoStream", "data/bike/streams/2030-03-13.json", "data/bike/streams/2030-03-13.missing.json"),
        // A workout whose recording ended at the stop: Garmin's own readings after it (kind garmin_2min).
        ("-PaceForgeHRRGarmin", "data/details/9000000001.json", "data/details/9000000001.garmin.json"),
        // Insights v2 with little data behind it (every item's "not enough data" state), and no insights-v2.json at all.
        ("-PaceForgeInsightsSparse", "data/insights-v2.json", "data/insights-v2.sparse.json"),
        ("-PaceForgeInsightsMissing", "data/insights-v2.json", "data/insights-v2.missing.json"),
        // Daily intel: a vital far out of its range (the red Health monitor tile and its alert), every item unavailable, and no file.
        ("-PaceForgeIntelAlert", "data/daily-intel.json", "data/daily-intel.alert.json"),
        ("-PaceForgeIntelUnavailable", "data/daily-intel.json", "data/daily-intel.unavailable.json"),
        ("-PaceForgeIntelMissing", "data/daily-intel.json", "data/daily-intel.missing.json"),
        // Phase 4 documents: every one unavailable (the server's own reason), none served, a fresh install with no streak alive,
        // and a Journal impact with nothing clear yet.
        ("-PaceForgePhase4Unavailable", "data/healthspan.json", "data/healthspan.unavailable.json"),
        ("-PaceForgePhase4Unavailable", "data/journal-impact.json", "data/journal-impact.unavailable.json"),
        ("-PaceForgePhase4Unavailable", "data/highlights.json", "data/highlights.unavailable.json"),
        ("-PaceForgePhase4Unavailable", "data/monthly-report.json", "data/monthly-report.unavailable.json"),
        ("-PaceForgePhase4Unavailable", "data/my-plan.json", "data/my-plan.unavailable.json"),
        ("-PaceForgePhase4Missing", "data/healthspan.json", "data/healthspan.missing.json"),
        ("-PaceForgePhase4Missing", "data/journal-impact.json", "data/journal-impact.missing.json"),
        ("-PaceForgePhase4Missing", "data/highlights.json", "data/highlights.missing.json"),
        ("-PaceForgePhase4Missing", "data/monthly-report.json", "data/monthly-report.missing.json"),
        ("-PaceForgePhase4Missing", "data/my-plan.json", "data/my-plan.missing.json"),
        ("-PaceForgeNoStreak", "data/highlights.json", "data/highlights.nostreak.json"),
        ("-PaceForgeJournalImpactEmpty", "data/journal-impact.json", "data/journal-impact.empty.json"),
        // Things waiting on the athlete (the default fixture has none, so the Needs you card is absent).
        ("-PaceForgeNeedsYou", "data/needs-you.json", "data/needs-you.active.json"),
    ]
    #endif

    private static func fixtureKey(_ path: String) -> String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        for variant in fixtureVariants where variant.path == path && arguments.contains(variant.flag) {
            return variant.alternate
        }
        #endif
        return path
    }

    static var isConfigured: Bool { isFixture || SelfHostedPushClient.paceForgeIsConfigured }

    /// One GET, saved on the phone as the last good copy. In a UI-test fixture the file comes from the fixture and nothing is saved.
    static func fetch(_ path: String) async throws -> Data {
        let data = try await get(path)
        if isFixture { return data }
        PFStore.write(data, path: path)
        // The big documents only (state, fitness, activities, ...), so one refresh does not fill the breadcrumb ring.
        if data.count >= 100_000 { NoopDiag.crumb("pf.doc \(path)", ["bytes": Double(data.count)]) }
        return data
    }

    private static func get(_ path: String) async throws -> Data {
        if let files = fixture {
            #if DEBUG
            // Offline: every request fails, so the tab keeps showing what it read from the phone.
            if ProcessInfo.processInfo.arguments.contains("-PaceForgeFetchFails") { throw URLError(.notConnectedToInternet) }
            #endif
            guard let value = files[fixtureKey(path)] else { throw CocoaError(.fileNoSuchFile) }
            if let text = value as? String { return Data(text.utf8) }
            return try JSONSerialization.data(withJSONObject: value)
        }
        return try await SelfHostedPushClient.paceForgeGet(path)
    }

    /// `data/manifest.json`: the hash of every document, by path. nil when the server does not serve it (an older server, offline,
    /// a login page) or lists nothing: the caller then downloads every document as before. Not saved on the phone.
    static func fetchManifest() async -> [String: String]? {
        guard let data = try? await get("data/manifest.json") else { return nil }
        var hashes: [String: String] = [:]
        for (path, entry) in PFJ(data: data)["docs"].dict {
            if let sha = entry["sha1"].string { hashes[path] = sha.lowercased() }
        }
        return hashes.isEmpty ? nil : hashes
    }

    /// The server answered, or it did not; a missing optional document just leaves its section out.
    static func fetchOptional(_ path: String) async -> Data? {
        try? await fetch(path)
    }

    /// The one write the app makes: today's 1-5 "how do you feel" answer. Returns the server's answer body.
    /// In a UI-test fixture the `api/feel` entry stands in for the server, or the call fails when it has none.
    static func postFeel(_ value: Int) async throws -> Data {
        if let files = fixture {
            // `-PaceForgeFeelFails` makes the save fail, to capture the "couldn't save" message.
            if ProcessInfo.processInfo.arguments.contains("-PaceForgeFeelFails") { throw URLError(.notConnectedToInternet) }
            guard let reply = files["api/feel"] else { throw CocoaError(.fileNoSuchFile) }
            return try JSONSerialization.data(withJSONObject: reply)
        }
        return try await SelfHostedPushClient.paceForgePost("api/feel", body: ["feel": value])
    }

    /// The app's only other write: a typed tape or field-test phrase to `api/app/log`. Returns the status and body
    /// whatever the status, so the sheet can show the server's own plain-English refusal. In a UI-test fixture the
    /// `api/app/log` entry stands in for the server (200), or the call fails when it has none.
    static func postLog(kind: PFLogKind, text: String) async throws -> (status: Int, data: Data) {
        if let files = fixture {
            guard let reply = files["api/app/log"] else { throw CocoaError(.fileNoSuchFile) }
            let data = try JSONSerialization.data(withJSONObject: reply)
            return (200, data)
        }
        return try await SelfHostedPushClient.paceForgePostReturningStatus(
            "api/app/log", body: PFLog.requestBody(kind: kind, text: text))
    }

    /// `POST api/app/answer` with the app bearer: one answer to a Needs you item. Returns the status and body whatever the
    /// status, so the card can show the server's own plain-English refusal. In a UI-test fixture the `api/app/answer` entry
    /// stands in for the server (200), or the call fails when it has none or `-PaceForgeAnswerFails` is set.
    static func postAnswer(_ body: [String: Any]) async throws -> (status: Int, data: Data) {
        if let files = fixture {
            if ProcessInfo.processInfo.arguments.contains("-PaceForgeAnswerFails") { throw URLError(.notConnectedToInternet) }
            guard let reply = files["api/app/answer"] else { throw CocoaError(.fileNoSuchFile) }
            return (200, try JSONSerialization.data(withJSONObject: reply))
        }
        return try await SelfHostedPushClient.paceForgePostReturningStatus("api/app/answer", body: body)
    }

    /// One line for the error card: the server host and why the request failed. No token, no path.
    static func failureDetail(_ error: Error) -> String {
        let host = SelfHostedPushClient.paceForgeHost ?? "no endpoint"
        let reason: String
        switch error {
        case let failure as SelfHostedPushClient.Failure:
            switch failure {
            case .httpStatus(let code, _): reason = "HTTP \(code)"
            default: reason = failure.localizedDescription
            }
        case let urlError as URLError:
            reason = "\(urlError.code.rawValue) \(urlError.localizedDescription)"
        case is CocoaError:
            reason = "unreadable data"
        default:
            reason = error.localizedDescription
        }
        return "\(host): \(reason)"
    }

    static func isCancelled(_ error: Error) -> Bool {
        (error as? URLError)?.code == .cancelled || error is CancellationError
    }
}

/// Last good responses, kept in Application Support so the tab opens instantly offline.
enum PFStore {
    private static var directory: URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("PaceForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(_ path: String) -> URL? {
        directory?.appendingPathComponent(path.replacingOccurrences(of: "/", with: "__"))
    }

    static func write(_ data: Data, path: String) {
        guard let url = file(path) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func read(path: String) -> Data? {
        guard let url = file(path) else { return nil }
        return try? Data(contentsOf: url)
    }

    #if DEBUG
    static func remove(path: String) {
        guard let url = file(path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
    #endif

    static func savedAt(path: String) -> Date? {
        guard let url = file(path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    static func cachedBundle() -> PFRawBundle? { PFRawBundle.cached(read: { read(path: $0) }) }
}

/// What the tab shows: nothing yet, a first load, the "set up sync" prompt, an error or data.
enum PFPhase: Equatable {
    case loading
    case notSetUp
    case failed(String)
    case ready
}

/// A session's results documents, fetched when its results sheet opens.
struct PFSessionResults {
    var detail: PFDetail?
    var analysis: String?
}

@MainActor
final class PFModel: ObservableObject {
    @Published private(set) var phase: PFPhase = .loading
    @Published private(set) var snapshot: PFSnapshot?
    @Published private(set) var isRefreshing = false
    /// Set while saved data is on screen because the last refresh failed.
    @Published private(set) var offlineNote: String?
    /// Host and reason of the last failed refresh, shown as a caption under the generic message.
    @Published private(set) var failureDetail: String?
    @Published private(set) var savedAt: Date?

    /// Why a Needs you answer was not saved, by item id; cleared when that item is answered again.
    @Published private(set) var needsNotes: [String: String] = [:]

    private var lastSuccess: Date?
    /// Needs you ids answered successfully: a refresh that started before the answer must not bring them back.
    private var needsAnswered: Set<String> = []
    private var needsInFlight: Set<String> = []
    /// Idempotency keys by answer signature, so a retry after a lost reply cannot apply the answer twice.
    private var needsKeys: [String: String] = [:]
    /// The coordinator's generation of the snapshot on screen: the same generation again means nothing new to apply.
    private var appliedGeneration = -1
    /// The one load in flight. It runs in its own task so SwiftUI cancelling a caller (`.task` re-run,
    /// `.refreshable` ending, a tab switch) cannot cancel the network requests with URLError.cancelled.
    private var inFlight: Task<Void, Never>?

    /// Called when the tab opens; skips the network when the data is only seconds old.
    func refreshIfStale() async {
        if let lastSuccess, Date().timeIntervalSince(lastSuccess) < 20, snapshot != nil { return }
        await refresh()
    }

    /// Overlapping callers share the load already running instead of starting or skipping their own.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        isRefreshing = true
        defer { isRefreshing = false }

        guard PFAPI.isConfigured else {
            snapshot = nil
            phase = .notSetUp
            return
        }
        let today = PFAPI.todayISO
        let coordinator = PFRefreshCoordinator.shared
        if snapshot == nil, PFAPI.usesPhoneState {
            // The saved documents (about 1.5 MB of JSON) are read, parsed and built by the coordinator, off the main thread: on a
            // phone that work blocked the tab for a noticeable time on every first open.
            if let cached = await coordinator.cachedSnapshot(today: today), snapshot == nil, let saved = cached.snapshot {
                apply(saved, generation: cached.generation)
                savedAt = PFStore.savedAt(path: "api/state")
                phase = .ready
            }
        }
        do {
            let outcome = try await coordinator.refresh(.everything)
            // The same generation is the snapshot already on screen: neither the tab nor NOOP Today (which observes the shared
            // stores) re-renders for nothing.
            if let built = outcome.snapshot, outcome.generation != appliedGeneration || snapshot == nil {
                apply(built, generation: outcome.generation)
            }
            savedAt = Date()
            lastSuccess = Date()
            offlineNote = nil
            failureDetail = nil
            phase = .ready
        } catch {
            // A request that was cancelled even after a retry says nothing about the server, so it must
            // not replace what is on screen with an "offline" note.
            if PFAPI.isCancelled(error), snapshot != nil { return }
            failureDetail = PFAPI.failureDetail(error)
            if snapshot != nil {
                offlineNote = "Can't reach PaceForge. Showing the data last saved on this iPhone."
            } else {
                phase = .failed("Can't reach PaceForge")
            }
        }
    }

    private func apply(_ built: PFSnapshot, generation: Int) {
        NoopDiag.measure("pf.apply") {
            snapshot = built
            // Answered items leave the list for good once the server's own list no longer has them.
            needsAnswered.formIntersection(built.needsYou.map { $0.id })
            if !needsAnswered.isEmpty { snapshot?.needsYou.removeAll { needsAnswered.contains($0.id) } }
        }
        appliedGeneration = generation
    }

    /// Files today's feel answer. The card shows it at once; on a failure the previous summary comes back
    /// and this returns false. The server's own summary (with the fresh agreement sentence) replaces the
    /// optimistic one when it parses. Both the replacement and the rollback only touch the summary while it
    /// is still the optimistic one: a refresh that landed in between holds newer server data and wins.
    func submitFeel(_ value: Int) async -> Bool {
        guard (1...5).contains(value), var current = snapshot, let before = current.feel else { return false }
        let optimistic = before.answering(value)
        current.feel = optimistic
        snapshot = current
        do {
            let data = try await PFAPI.postFeel(value)
            if let saved = PFWave2Parse.feelSaved(PFJ(data: data)), var latest = snapshot, latest.feel == optimistic {
                latest.feel = saved.summary ?? latest.feel?.answering(saved.feel)
                snapshot = latest
            }
            if let latest = snapshot { await PFReminders.update(for: latest) }
            return true
        } catch {
            if var latest = snapshot, latest.feel == optimistic {
                latest.feel = before
                snapshot = latest
            }
            return false
        }
    }

    /// Sends one Needs you answer. The item leaves the card at once; the server's fresh list replaces it on success, and on any
    /// failure the item comes back with the reason in `needsNotes`. The reply is read off the main thread.
    func submitAnswer(_ answer: PFNeedsAnswer, for item: PFNeedsItem) async {
        guard !needsInFlight.contains(item.id), var current = snapshot,
              let index = current.needsYou.firstIndex(where: { $0.id == item.id }) else { return }
        needsInFlight.insert(item.id)
        needsNotes[item.id] = nil
        current.needsYou.remove(at: index)
        snapshot = current

        let signature = answer.signature(for: item.id)
        let key = needsKeys[signature] ?? "ios-" + UUID().uuidString.lowercased()
        needsKeys[signature] = key
        var body = answer.body
        body["key"] = key
        let outcome: PFAnswerOutcome
        do {
            let reply = try await PFAPI.postAnswer(body)
            outcome = await Task.detached(priority: .userInitiated) {
                PFAnswerOutcome.from(status: reply.status, data: reply.data)
            }.value
        } catch {
            outcome = .unreachable
        }
        needsInFlight.remove(item.id)

        guard outcome.isSaved else {
            needsNotes[item.id] = outcome.message
            if var latest = snapshot, !latest.needsYou.contains(where: { $0.id == item.id }) {
                latest.needsYou.insert(item, at: min(index, latest.needsYou.count))
                snapshot = latest
            }
            return
        }
        needsKeys[signature] = nil
        needsAnswered.insert(item.id)
        if let fresh = outcome.fresh, var latest = snapshot {
            latest.needsYou = fresh.filter { !needsAnswered.contains($0.id) }
            snapshot = latest
        }
        // What the answer changed (a pace, a plan) reaches the other cards on the next load. A fixture has no server to ask.
        if !PFAPI.isFixture { Task { await refresh() } }
    }

    /// Logs one tape or field-test phrase and, when the server took it, refreshes so the new numbers show at once.
    /// The outcome carries the server's confirmation or its plain-English reason for refusing.
    func submitLog(kind: PFLogKind, text: String) async -> PFLogOutcome {
        let outcome: PFLogOutcome
        do {
            let answer = try await PFAPI.postLog(kind: kind, text: text)
            outcome = PFLogOutcome.from(status: answer.status, body: answer.data)
        } catch {
            return .unreachable
        }
        if outcome.isSaved { await refresh() }
        return outcome
    }

    /// The details file and the coach's analysis for one activity; each falls back to the saved copy.
    func results(for activityId: String) async -> PFSessionResults {
        async let detailData = Self.fetchWithCache("data/details/\(activityId).json")
        async let analysisData = Self.fetchWithCache("data/analyses/\(activityId).md")
        var out = PFSessionResults()
        if let data = await detailData {
            let parsed = PFBuilder.detail(PFJ(data: data))
            if !parsed.samples.isEmpty || !parsed.splits.isEmpty || !parsed.zones.isEmpty { out.detail = parsed }
        }
        if let data = await analysisData, let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { out.analysis = trimmed }
        }
        return out
    }

    private static func fetchWithCache(_ path: String) async -> Data? {
        if let data = await PFAPI.fetchOptional(path) { return data }
        return PFAPI.usesPhoneState ? PFStore.read(path: path) : nil
    }
}
