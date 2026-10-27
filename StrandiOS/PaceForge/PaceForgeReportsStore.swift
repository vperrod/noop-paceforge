import SwiftUI

// Where the expert reports live on the phone. The Reports screen and the Expert reading card on Today read the same store, so a
// report fetched for one is not fetched again for the other. Read-only: nothing here writes to the server.

@MainActor
final class PFReportsStore: ObservableObject {
    static let shared = PFReportsStore()

    static let indexPath = "data/reports/index.json"
    static let latestDailyPath = "data/expert-panel.json"
    static let runsPath = "data/expert-panel-runs.json"
    static let capabilitiesPath = "data/capabilities.json"

    enum IndexState: Equatable {
        case notLoaded, loading, ready, notSetUp, failed
    }

    @Published private(set) var indexState: IndexState = .notLoaded
    @Published private(set) var rows: [PFReportKind: [PFReportRow]] = [:]
    @Published private(set) var reports: [String: PFReport] = [:]
    @Published private(set) var failedReports: Set<String> = []
    /// The latest daily reading (data/expert-panel.json), for the card on Today.
    @Published private(set) var latestDaily: PFReport?
    /// The daily job's runs of the last days, keyed by the day (data/expert-panel-runs.json). Empty until the file is on the phone.
    @Published private(set) var runs: [String: [PFReportRun]] = [:]
    /// What this athlete's devices give (data/capabilities.json). nil until the file is on the phone, which shows everything.
    @Published private(set) var capabilities: PFCapabilities?

    /// False only when the server says this athlete has no reports (the expert jobs are not scheduled for the account).
    var showsReports: Bool { capabilities?.showsReports ?? true }

    private var latestFetch: Date?

    static func reportID(_ kind: PFReportKind, _ key: String) -> String { "\(kind.rawValue)/\(key)" }

    static func reportPath(_ kind: PFReportKind, _ key: String) -> String { "data/reports/\(kind.rawValue)/\(key).json" }

    /// The server's copy, or the copy the last good fetch left on the phone when it cannot be reached.
    private func data(_ path: String) async -> Data? {
        var data = await PFAPI.fetchOptional(path)
        if data == nil, PFAPI.usesPhoneState { data = PFStore.read(path: path) }
        return data
    }

    func loadIndex() async {
        guard PFAPI.isConfigured else {
            indexState = .notSetUp
            return
        }
        if rows.isEmpty { indexState = .loading }
        guard let fetched = await data(Self.indexPath) else {
            if rows.isEmpty { indexState = .failed }
            return
        }
        let json = PFJ(data: fetched)
        var next: [PFReportKind: [PFReportRow]] = [:]
        for kind in PFReportKind.allCases { next[kind] = PFReportParse.rows(json, kind: kind) }
        if rows != next { rows = next }
        indexState = .ready
    }

    func loadCapabilities() async {
        guard PFAPI.isConfigured else { return }
        guard let fetched = await data(Self.capabilitiesPath) else { return }
        let parsed = PFReportParse.capabilities(PFJ(data: fetched))
        if capabilities != parsed { capabilities = parsed }
    }

    func loadRuns() async {
        guard PFAPI.isConfigured else { return }
        guard let fetched = await data(Self.runsPath) else { return }
        let parsed = PFReportParse.runs(PFJ(data: fetched))
        if runs != parsed { runs = parsed }
    }

    func loadReport(_ kind: PFReportKind, key: String) async {
        let id = Self.reportID(kind, key)
        guard PFAPI.isConfigured else { return }
        guard let fetched = await data(Self.reportPath(kind, key)),
              let report = PFReportParse.report(PFJ(data: fetched), kind: kind) else {
            if reports[id] == nil { failedReports.insert(id) }
            return
        }
        if reports[id] != report { reports[id] = report }
        failedReports.remove(id)
    }

    /// Today asks on every appearance; the file is only fetched again when the copy is two minutes old.
    func refreshLatestIfStale() async {
        if let latestFetch, Date().timeIntervalSince(latestFetch) < 120 { return }
        guard PFAPI.isConfigured else { return }
        await loadCapabilities()
        guard let fetched = await data(Self.latestDailyPath) else { return }
        latestFetch = Date()
        let parsed = PFReportParse.report(PFJ(data: fetched), kind: .daily)
        if latestDaily != parsed { latestDaily = parsed }
        await loadRuns()
    }
}
