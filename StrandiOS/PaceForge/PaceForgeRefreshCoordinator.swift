import CryptoKit
import Foundation

// BETA (Settings > Tools > New PaceForge refresh, off by default; see PaceForgeBeta.swift). Nothing here runs unless the switch
// was on at launch. Every caller wraps a call in a fallback to the build 477 refresh.
//
// The one place PaceForge's documents are refreshed when the beta is on. NOOP Today, the PaceForge tab, the background task and
// the two shared stores ask this actor, which
// - runs one refresh at a time and lets overlapping callers share it (a caller that needs more waits for one run that covers
//   everything the waiting callers asked for),
// - asks the server for `data/manifest.json` first (a hash for every document) and downloads only the documents whose hash
//   differs from the copy saved on the phone; a server without the manifest gets today's full fetch,
// - parses only the documents the build needs, one after the other, builds on a thread with a large stack, and drops the parsed
//   trees as soon as the snapshot is assembled,
// - publishes the snapshot, the widget summary (on the main actor) and the two shared stores only when something they are built
//   from changed,
// - leaves `refresh.beta start` / `refresh.beta end` breadcrumbs: documents downloaded, documents already current, milliseconds
//   and the memory footprint before, after parsing and after.
// Read-only: nothing here writes to the server.

struct PFRefreshOutcome {
    /// The newest snapshot built from the server's documents; nil until one was built.
    var snapshot: PFSnapshot?
    /// Changes with every snapshot built, so a caller applies the snapshot only when it has not applied this one.
    var generation: Int
}

/// What one document request came back with. The body itself is saved on the phone by `PFAPI.fetch`; it is kept here only when
/// nothing is saved (a UI-test fixture).
private enum PFDocFetch {
    case body(data: Data?, hash: String, bytes: Int)
    /// The server has no such document (HTTP 404).
    case absent(Error)
    /// The request failed (offline, timeout, a login page): the copy on the phone stays.
    case failed(Error)
}

private struct PFRefreshStats {
    var fetched = 0
    var unchanged = 0
    var bytes = 0
    var usedManifest = false
    var built = false
    var parsedFootprintMB = 0.0
}

actor PFRefreshCoordinator {
    static let shared = PFRefreshCoordinator()

    /// The saved copy's hash of every document, next to the saved documents: a document whose hash equals the manifest's is not
    /// downloaded again.
    private static let hashesPath = "manifest-cache.json"
    private static let summaryRepublishAge: TimeInterval = 6 * 3600

    private var hashes: [String: String] = [:]
    private var hashesLoaded = false
    private var hashesChanged = false
    /// Documents the server answered 404 for in this run of the app.
    private var absent: Set<String> = []
    /// Documents that changed since `built` was made (or that the snapshot has not seen).
    private var dirty: Set<String> = []
    private var built: PFSnapshot?
    private var builtDay: String?
    private var generation = 0
    private var lastDone: [PFRefreshScope: Date] = [:]
    private var lastSummaryPublish: Date?
    private var publishedIntel = false
    private var publishedPhase4 = false
    private var stats = PFRefreshStats()

    private final class Flight {
        var scope: PFRefreshScope
        var task: Task<Result<PFRefreshOutcome, Error>, Never>?
        init(scope: PFRefreshScope) { self.scope = scope }
    }

    private var running: Flight?
    private var waiting: Flight?

    private var isBusy: Bool { running != nil || waiting != nil }

    // MARK: Entry points

    /// Refreshes now. A caller whose scope the running refresh covers shares it; the others share the one run that starts after
    /// it and covers all of them.
    func refresh(_ scope: PFRefreshScope) async throws -> PFRefreshOutcome {
        let flight: Flight
        if let running, running.scope.isSuperset(of: scope) {
            flight = running
        } else if let waiting {
            waiting.scope.formUnion(scope)
            flight = waiting
        } else {
            flight = enqueue(scope)
        }
        guard let task = flight.task else { throw CancellationError() }
        return try await task.value.get()
    }

    /// Refreshes unless every part of `scope` was refreshed less than `maxAge` seconds ago.
    func refreshIfStale(_ scope: PFRefreshScope, maxAge: TimeInterval) async throws -> PFRefreshOutcome {
        let now = Date()
        let isCurrent = PFRefreshScope.parts.filter { scope.contains($0) }.allSatisfy { part in
            lastDone[part].map { now.timeIntervalSince($0) < maxAge } ?? false
        }
        if isCurrent, !scope.contains(.snapshot) || built != nil {
            return PFRefreshOutcome(snapshot: built, generation: generation)
        }
        return try await refresh(scope)
    }

    /// The snapshot the saved documents make, for a tab that opens before the network answers. The one already built when there
    /// is one; nil when nothing usable is saved.
    ///
    /// While a refresh is in flight it owns `built`, `dirty` and `generation`: this then only reports the last built value and
    /// leaves the state alone (the refresh that follows shares the flight).
    func cachedSnapshot(today: String) async -> PFRefreshOutcome? {
        if let built, builtDay == today { return PFRefreshOutcome(snapshot: built, generation: generation) }
        if isBusy { return built.map { PFRefreshOutcome(snapshot: $0, generation: generation) } }
        let cached = await Self.buildFromSaved(today: today)
        // The build ran off the actor: a refresh may have started, or finished, meanwhile, and its state wins.
        if let built, builtDay == today { return PFRefreshOutcome(snapshot: built, generation: generation) }
        if isBusy { return built.map { PFRefreshOutcome(snapshot: $0, generation: generation) } }
        guard let cached else { return nil }
        built = cached
        builtDay = today
        dirty = []
        generation += 1
        return PFRefreshOutcome(snapshot: cached, generation: generation)
    }

    // MARK: Single flight

    private func enqueue(_ scope: PFRefreshScope) -> Flight {
        let flight = Flight(scope: scope)
        let previous = running
        if previous == nil { running = flight } else { waiting = flight }
        flight.task = Task { [self] in
            if let previous, let earlier = previous.task { _ = await earlier.value }
            begin(flight)
            let result: Result<PFRefreshOutcome, Error>
            do { result = .success(try await run(flight.scope)) } catch { result = .failure(error) }
            end(flight)
            return result
        }
        return flight
    }

    private func begin(_ flight: Flight) {
        running = flight
        if waiting === flight { waiting = nil }
    }

    private func end(_ flight: Flight) {
        if running === flight { running = nil }
    }

    // MARK: One refresh

    private func run(_ scope: PFRefreshScope) async throws -> PFRefreshOutcome {
        let start = DispatchTime.now().uptimeNanoseconds
        let before = NoopDiagSampler.footprintMB()
        NoopDiag.crumb("refresh.beta start", ["scope": Double(scope.rawValue), "mem_before_mb": before])
        func leaveCrumb(failed: Bool) {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            NoopDiag.crumb("refresh.beta end", [
                "docs_fetched": Double(stats.fetched),
                "docs_unchanged": Double(stats.unchanged),
                "ms": ms.rounded(),
                "bytes": Double(stats.bytes),
                "manifest": stats.usedManifest ? 1 : 0,
                "built": stats.built ? 1 : 0,
                "scope": Double(scope.rawValue),
                "failed": failed ? 1 : 0,
                "mem_before_mb": before,
                "mem_parsed_mb": stats.parsedFootprintMB,
                "mem_after_mb": NoopDiagSampler.footprintMB(),
            ])
        }
        do {
            let outcome: PFRefreshOutcome
            do { outcome = try await perform(scope) }
            // A request cancelled client-side (URLError.cancelled) says nothing about the server: one more attempt.
            catch where PFAPI.isCancelled(error) { outcome = try await perform(scope) }
            leaveCrumb(failed: false)
            return outcome
        } catch {
            leaveCrumb(failed: true)
            throw error
        }
    }

    private func perform(_ scope: PFRefreshScope) async throws -> PFRefreshOutcome {
        stats = PFRefreshStats()
        loadHashesIfNeeded()
        let specs = PFDocs.specs(for: scope)

        let manifest = await PFAPI.fetchManifest()
        stats.usedManifest = manifest != nil
        var toFetch: [PFDocSpec] = []
        for spec in specs {
            if let sha = manifest?[spec.path], hashes[spec.path] == sha, PFStore.savedAt(path: spec.path) != nil {
                stats.unchanged += 1
            } else {
                toFetch.append(spec)
            }
        }

        let interval = NoopDiag.begin("pf.fetch")
        let results = await Self.fetchAll(toFetch)
        var downloaded = 0
        for item in results {
            if case .body(_, _, let size) = item.result { downloaded += size }
        }
        interval.end(["bytes": Double(downloaded)])
        // Without state or fitness there is no snapshot: the refresh fails as a whole, as it always did.
        for (spec, result) in results where spec.isRequired {
            switch result {
            case .failed(let error), .absent(let error): throw error
            case .body: break
            }
        }

        // Bodies are on the phone already (`PFAPI.fetch` saved them); only a fixture, which saves nothing, keeps them here.
        var fixtureBodies: [String: Data] = [:]
        var changed = Set<String>()
        for (spec, result) in results {
            switch result {
            case .body(let data, let hash, let size):
                stats.fetched += 1
                stats.bytes += size
                absent.remove(spec.path)
                if hashes[spec.path] == hash {
                    stats.unchanged += 1
                } else {
                    hashes[spec.path] = hash
                    hashesChanged = true
                    if spec.key != nil { changed.insert(spec.path) }
                }
                if let data { fixtureBodies[spec.path] = data }
            case .absent:
                if hashes.removeValue(forKey: spec.path) != nil { hashesChanged = true }
                if absent.insert(spec.path).inserted, spec.key != nil { changed.insert(spec.path) }
            case .failed:
                break
            }
        }
        dirty.formUnion(changed)

        let today = PFAPI.todayISO
        var rebuilt = false
        var fullRebuild = false
        var changedForBuild = Set<String>()
        if scope.contains(.snapshot), built == nil || builtDay != today || !dirty.isEmpty {
            let previous = built
            fullRebuild = previous == nil || builtDay != today
            changedForBuild = dirty
            let needed = PFBuilder.documents(needed: today, previous: previous, changed: changedForBuild)
            let paths = changedForBuild
            let gone = absent
            let bodies = fixtureBodies
            // Parsed in the build thread, in one place, and gone when it returns: only the snapshot leaves.
            let product = await PFBuildThread.run("refresh") { () -> (PFSnapshot?, [String], Double) in
                autoreleasepool { () -> (PFSnapshot?, [String], Double) in
                    let assembled = Self.assemble(needed: needed, bodies: bodies, absent: gone)
                    let parsedMB = NoopDiagSampler.footprintMB()
                    let snapshot = NoopDiag.measure("pf.build.fetched") {
                        PFBuilder.snapshot(from: assembled.raw, today: today, previous: previous, changed: paths)
                    }
                    return (snapshot, assembled.unreadable, parsedMB)
                }
            }
            stats.parsedFootprintMB = product.2
            // A saved copy that cannot be read is downloaded again on the next refresh.
            for path in product.1 where hashes.removeValue(forKey: path) != nil { hashesChanged = true }
            guard let result = product.0 else { throw CocoaError(.fileReadCorruptFile) }
            self.built = result
            builtDay = today
            dirty = []
            generation += 1
            rebuilt = true
            stats.built = true
        }
        persistHashes()

        if scope.contains(.snapshot), let built {
            let summaryChanged = fullRebuild || !changedForBuild.isDisjoint(with: PFDocs.summaryInputs)
            let isOverdue = lastSummaryPublish.map { Date().timeIntervalSince($0) > Self.summaryRepublishAge } ?? true
            if (rebuilt && summaryChanged) || isOverdue {
                // The widget summary and the reminders are written on the main actor, as they were when the model published them.
                let summary = NoopDiag.begin("pf.summary.publish")
                await MainActor.run { PFSummaryWriter.publish(built) }
                summary.end()
                lastSummaryPublish = Date()
            }
            let touched = fullRebuild ? Set(PFDocs.all.map { $0.path }) : changedForBuild
            if !publishedIntel || !touched.isDisjoint(with: [PFDocs.dailyIntel]) {
                await publishIntel(built.dailyIntel)
            }
            if !publishedPhase4 || !touched.isDisjoint(with: PFDocPath.all) {
                await publishPhase4(built.intelDocs)
            }
        } else {
            if scope.contains(.dailyIntel), !publishedIntel || changed.contains(PFDocs.dailyIntel) {
                let doc = Self.document(PFDocs.dailyIntel, bodies: fixtureBodies, absent: absent)
                await publishIntel(PFDailyIntelParse.document(doc))
            }
            if scope.contains(.phase4), !publishedPhase4 || !changed.isDisjoint(with: PFDocPath.all) {
                let (bodies, gone) = (fixtureBodies, absent)
                await publishPhase4(PFIntelDocsParse.docs(
                    healthspan: Self.document(PFDocPath.healthspan, bodies: bodies, absent: gone),
                    journalImpact: Self.document(PFDocPath.journalImpact, bodies: bodies, absent: gone),
                    highlights: Self.document(PFDocPath.highlights, bodies: bodies, absent: gone),
                    monthlyReport: Self.document(PFDocPath.monthlyReport, bodies: bodies, absent: gone),
                    myPlan: Self.document(PFDocPath.myPlan, bodies: bodies, absent: gone)))
            }
        }

        let now = Date()
        for part in PFRefreshScope.parts where scope.contains(part) { lastDone[part] = now }
        return PFRefreshOutcome(snapshot: built, generation: generation)
    }

    // MARK: Documents

    /// The saved documents, parsed and built into a snapshot on the big-stack thread; nil when nothing usable is saved.
    private static func buildFromSaved(today: String) async -> PFSnapshot? {
        await PFBuildThread.run("cached") { () -> PFSnapshot? in
            autoreleasepool { () -> PFSnapshot? in
                guard let raw = NoopDiag.measure("pf.cache.read", { PFStore.cachedBundle() }) else { return nil }
                return NoopDiag.measure("pf.build.cached") { PFBuilder.snapshot(from: raw, today: today) }
            }
        }
    }

    /// The parsed documents the builder will read, one after the other: the ones just downloaded (a fixture), else the saved
    /// copy. A document the server does not have reads as missing, never as the copy an earlier version left behind. The paths of
    /// saved copies that could not be read come back too.
    private static func assemble(needed: Set<String>, bodies: [String: Data],
                                 absent: Set<String>) -> (raw: PFRawBundle, unreadable: [String]) {
        var raw = PFRawBundle()
        var unreadable: [String] = []
        for spec in PFDocs.all {
            guard let key = spec.key, needed.contains(spec.path) else { continue }
            let json = document(spec.path, bodies: bodies, absent: absent)
            if !json.exists, !absent.contains(spec.path) { unreadable.append(spec.path) }
            raw[keyPath: key] = json
        }
        return (raw, unreadable)
    }

    private static func document(_ path: String, bodies: [String: Data], absent: Set<String>) -> PFJ {
        if let data = bodies[path] { return PFJ(data: data) }
        if absent.contains(path) || !PFAPI.usesPhoneState { return PFJ(nil) }
        return PFJ(data: PFStore.read(path: path))
    }

    private func publishIntel(_ value: PFDailyIntel?) async {
        await MainActor.run { PFDailyIntelStore.shared.update(value) }
        publishedIntel = true
    }

    private func publishPhase4(_ value: PFIntelDocs) async {
        await MainActor.run { PFPhase4Store.shared.update(value) }
        publishedPhase4 = true
    }

    // MARK: Hash cache

    private func loadHashesIfNeeded() {
        guard !hashesLoaded else { return }
        hashesLoaded = true
        guard PFAPI.usesPhoneState, let data = PFStore.read(path: Self.hashesPath),
              let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else { return }
        hashes = saved
    }

    private func persistHashes() {
        guard hashesChanged, PFAPI.usesPhoneState else { return }
        hashesChanged = false
        guard let data = try? JSONSerialization.data(withJSONObject: hashes) else { return }
        PFStore.write(data, path: Self.hashesPath)
    }

    // MARK: Network

    /// Every request at once. A downloaded document is saved by `PFAPI.fetch`, hashed and let go: nothing is parsed here.
    private static func fetchAll(_ specs: [PFDocSpec]) async -> [(spec: PFDocSpec, result: PFDocFetch)] {
        let keepsBodies = !PFAPI.usesPhoneState
        return await withTaskGroup(of: (Int, PFDocFetch).self, returning: [(spec: PFDocSpec, result: PFDocFetch)].self) { group in
            for (index, spec) in specs.enumerated() {
                let path = spec.path
                group.addTask {
                    let result = await PFRefreshCoordinator.fetchOne(path, keepsBody: keepsBodies)
                    return (index, result)
                }
            }
            var all: [(Int, PFDocFetch)] = []
            for await item in group { all.append(item) }
            return all.sorted { $0.0 < $1.0 }.map { (spec: specs[$0.0], result: $0.1) }
        }
    }

    private static func fetchOne(_ path: String, keepsBody: Bool) async -> PFDocFetch {
        do {
            let data = try await PFAPI.fetch(path)
            return .body(data: keepsBody ? data : nil, hash: sha1(data), bytes: data.count)
        } catch {
            return isMissing(error) ? .absent(error) : .failed(error)
        }
    }

    private static func isMissing(_ error: Error) -> Bool {
        if let failure = error as? SelfHostedPushClient.Failure, case .httpStatus(let code, _) = failure { return code == 404 }
        return (error as? CocoaError)?.code == .fileNoSuchFile
    }

    private static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
