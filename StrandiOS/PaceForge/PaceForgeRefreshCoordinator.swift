import CryptoKit
import Foundation

// The one place PaceForge's documents are refreshed. NOOP Today, the PaceForge tab, the background task and every store that
// used to fetch for itself ask this actor, which
// - runs one refresh at a time and lets overlapping callers share it (a caller that needs more waits for one run that covers
//   everything the waiting callers asked for),
// - asks the server for `data/manifest.json` first (a hash for every document) and downloads only the documents whose hash
//   differs from the copy saved on the phone; a server without the manifest gets today's full fetch,
// - parses the changed documents off the main thread and builds the snapshot again only from them (`PFBuilder`, `PFLeaf`),
// - publishes the snapshot, the widget summary and the two shared stores only when something they are built from changed,
// - leaves a `refresh` breadcrumb per run: documents downloaded, documents already current, milliseconds.
// Read-only: nothing here writes to the server.

struct PFRefreshOutcome {
    /// The newest snapshot built from the server's documents; nil until one was built.
    var snapshot: PFSnapshot?
    /// Changes with every snapshot built, so a caller applies the snapshot only when it has not applied this one.
    var generation: Int
}

/// What one document request came back with.
private enum PFDocFetch {
    case body(json: PFJ?, hash: String, bytes: Int)
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
    func cachedSnapshot(today: String) -> PFRefreshOutcome? {
        if let built, builtDay == today { return PFRefreshOutcome(snapshot: built, generation: generation) }
        guard let raw = NoopDiag.measure("pf.cache.read", { PFStore.cachedBundle() }) else { return nil }
        guard let cached = NoopDiag.measure("pf.build.cached", { PFBuilder.snapshot(from: raw, today: today) }) else { return nil }
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
        func leaveCrumb(failed: Bool) {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
            NoopDiag.crumb("refresh", [
                "refresh.docs_fetched": Double(stats.fetched),
                "refresh.docs_unchanged": Double(stats.unchanged),
                "refresh.ms": ms.rounded(),
                "refresh.bytes": Double(stats.bytes),
                "refresh.manifest": stats.usedManifest ? 1 : 0,
                "refresh.built": stats.built ? 1 : 0,
                "refresh.scope": Double(scope.rawValue),
                "refresh.failed": failed ? 1 : 0,
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

        var fresh: [String: PFJ] = [:]
        var changed = Set<String>()
        for (spec, result) in results {
            switch result {
            case .body(let json, let hash, let size):
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
                if let json { fresh[spec.path] = json }
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
            let raw = assemble(needed: needed, fresh: fresh)
            let changedPaths = changedForBuild
            let result = NoopDiag.measure("pf.build.fetched") {
                PFBuilder.snapshot(from: raw, today: today, previous: previous, changed: changedPaths)
            }
            guard let result else { throw CocoaError(.fileReadCorruptFile) }
            built = result
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
                NoopDiag.measure("pf.summary.publish") { PFSummaryWriter.publish(built) }
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
                await publishIntel(PFDailyIntelParse.document(document(PFDocs.dailyIntel, fresh: fresh)))
            }
            if scope.contains(.phase4), !publishedPhase4 || !changed.isDisjoint(with: PFDocPath.all) {
                await publishPhase4(PFIntelDocsParse.docs(
                    healthspan: document(PFDocPath.healthspan, fresh: fresh),
                    journalImpact: document(PFDocPath.journalImpact, fresh: fresh),
                    highlights: document(PFDocPath.highlights, fresh: fresh),
                    monthlyReport: document(PFDocPath.monthlyReport, fresh: fresh),
                    myPlan: document(PFDocPath.myPlan, fresh: fresh)))
            }
        }

        let now = Date()
        for part in PFRefreshScope.parts where scope.contains(part) { lastDone[part] = now }
        return PFRefreshOutcome(snapshot: built, generation: generation)
    }

    // MARK: Documents

    /// The parsed documents the builder will read: the ones just downloaded, else the saved copy. A document the server does not
    /// have reads as missing, never as the copy an earlier version left behind.
    private func assemble(needed: Set<String>, fresh: [String: PFJ]) -> PFRawBundle {
        var raw = PFRawBundle()
        for spec in PFDocs.all {
            guard let key = spec.key, needed.contains(spec.path) else { continue }
            let json = document(spec.path, fresh: fresh)
            // A saved copy that cannot be read is downloaded again on the next refresh.
            if !json.exists, !absent.contains(spec.path), hashes.removeValue(forKey: spec.path) != nil { hashesChanged = true }
            raw[keyPath: key] = json
        }
        return raw
    }

    private func document(_ path: String, fresh: [String: PFJ]) -> PFJ {
        if let json = fresh[path] { return json }
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

    /// Every request at once; each downloaded document is parsed on the request's own task, off the actor.
    private static func fetchAll(_ specs: [PFDocSpec]) async -> [(spec: PFDocSpec, result: PFDocFetch)] {
        await withTaskGroup(of: (Int, PFDocFetch).self, returning: [(spec: PFDocSpec, result: PFDocFetch)].self) { group in
            for (index, spec) in specs.enumerated() {
                let path = spec.path
                let shouldParse = spec.key != nil
                group.addTask { (index, await PFRefreshCoordinator.fetchOne(path, shouldParse: shouldParse)) }
            }
            var all: [(Int, PFDocFetch)] = []
            for await item in group { all.append(item) }
            return all.sorted { $0.0 < $1.0 }.map { (spec: specs[$0.0], result: $0.1) }
        }
    }

    private static func fetchOne(_ path: String, shouldParse: Bool) async -> PFDocFetch {
        do {
            let data = try await PFAPI.fetch(path)
            return .body(json: shouldParse ? PFJ(data: data) : nil, hash: sha1(data), bytes: data.count)
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
