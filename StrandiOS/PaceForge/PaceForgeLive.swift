import SwiftUI

/// Fetches PaceForge's JSON with the sync client's endpoint and Keychain token.
/// UI tests run without a server: `-PaceForgeFixture` serves the files from `PF_FIXTURE_JSON` instead.
enum PFAPI {
    /// Path (relative to the PaceForge root) -> JSON value or markdown text, for the UI-test fixture.
    private static let fixture: [String: Any]? = {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-PaceForgeFixture"),
              let text = ProcessInfo.processInfo.environment["PF_FIXTURE_JSON"],
              let data = text.data(using: .utf8),
              let files = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return files
        #else
        return nil
        #endif
    }()

    static var isFixture: Bool { fixture != nil }

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

    static var isConfigured: Bool { isFixture || SelfHostedPushClient.paceForgeIsConfigured }

    static func fetch(_ path: String) async throws -> Data {
        if let files = fixture {
            guard let value = files[path] else { throw CocoaError(.fileNoSuchFile) }
            if let text = value as? String { return Data(text.utf8) }
            return try JSONSerialization.data(withJSONObject: value)
        }
        let data = try await SelfHostedPushClient.paceForgeGet(path)
        PFStore.write(data, path: path)
        return data
    }

    /// The server answered, or it did not; a missing optional document just leaves its section out.
    static func fetchOptional(_ path: String) async -> Data? {
        try? await fetch(path)
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

    /// One more attempt when the first was cancelled client-side (URLError.cancelled, code -999).
    static func fetchBundleRetryingCancel() async throws -> PFRawBundle {
        do { return try await fetchBundle() }
        catch where isCancelled(error) { return try await fetchBundle() }
    }

    static func fetchBundle() async throws -> PFRawBundle {
        async let projection = fetchOptional("data/projection.json")
        async let body = fetchOptional("data/body.json")
        async let hyrox = fetchOptional("data/hyrox_analysis.json")
        async let activities = fetchOptional("data/activities.json")
        async let analyses = fetchOptional("data/analyses/index.json")
        async let bodyProgress = fetchOptional("data/body-progress.json")
        async let alerts = fetchOptional("data/alerts.json")
        async let readiness = fetchOptional("data/readiness-explained.json")
        // Not part of the bundle's view models: fetched so My Day finds it saved on the phone (PFStore).
        async let workoutMatches = fetchOptional("data/workout-matches.json")
        async let state = fetch("api/state")
        async let fitness = fetch("data/fitness.json")
        let (stateData, fitnessData) = try await (state, fitness)
        var raw = PFRawBundle()
        raw.state = PFJ(data: stateData)
        raw.fitness = PFJ(data: fitnessData)
        raw.projection = PFJ(data: await projection)
        raw.body = PFJ(data: await body)
        raw.hyrox = PFJ(data: await hyrox)
        raw.activities = PFJ(data: await activities)
        raw.analysesIndex = PFJ(data: await analyses)
        raw.bodyProgress = PFJ(data: await bodyProgress)
        raw.alerts = PFJ(data: await alerts)
        raw.readiness = PFJ(data: await readiness)
        _ = await workoutMatches
        return raw
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

    static func savedAt(path: String) -> Date? {
        guard let url = file(path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    static func cachedBundle() -> PFRawBundle? {
        guard let state = read(path: "api/state"), let fitness = read(path: "data/fitness.json") else { return nil }
        var raw = PFRawBundle()
        raw.state = PFJ(data: state)
        raw.fitness = PFJ(data: fitness)
        raw.projection = PFJ(data: read(path: "data/projection.json"))
        raw.body = PFJ(data: read(path: "data/body.json"))
        raw.hyrox = PFJ(data: read(path: "data/hyrox_analysis.json"))
        raw.activities = PFJ(data: read(path: "data/activities.json"))
        raw.analysesIndex = PFJ(data: read(path: "data/analyses/index.json"))
        raw.bodyProgress = PFJ(data: read(path: "data/body-progress.json"))
        raw.alerts = PFJ(data: read(path: "data/alerts.json"))
        raw.readiness = PFJ(data: read(path: "data/readiness-explained.json"))
        return raw
    }
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

    private var lastSuccess: Date?
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
        if snapshot == nil, !PFAPI.isFixture, let cached = PFStore.cachedBundle(),
           let built = PFBuilder.snapshot(from: cached, today: PFAPI.todayISO) {
            snapshot = built
            savedAt = PFStore.savedAt(path: "api/state")
            phase = .ready
        }
        do {
            let raw = try await PFAPI.fetchBundleRetryingCancel()
            guard let built = PFBuilder.snapshot(from: raw, today: PFAPI.todayISO) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            snapshot = built
            PFSummaryWriter.publish(built)
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
        return PFAPI.isFixture ? nil : PFStore.read(path: path)
    }
}
