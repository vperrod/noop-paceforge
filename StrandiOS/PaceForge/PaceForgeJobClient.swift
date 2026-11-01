import SwiftUI

// The network half of the job door (the pure half, PaceForgeJob.swift, is unit-tested): submit a job, follow a slow one, and a small
// observable that a view shows while its job is in flight.

enum PFJobClient {
    /// `POST api/app/job`. A fast job has run inline by the time this returns (`state` done, its `result` filled); a slow one is queued.
    /// Every call carries a `client_key`, made once per call. A small write that got no answer is kept for `PFJobRetry` and the call
    /// fails with `.queued`; doing the identical write again by hand reuses the waiting write's key.
    static func submit(_ job: PFJobName, inputs: [String: Any]) async -> Result<PFJobSubmission, PFJobError> {
        let encoded = job.isQueueable && !PFAPI.isFixture ? PFJobRetryList.encodeInputs(inputs) : nil
        let waitingKey = encoded.flatMap { PFJobRetryStore.waitingKey(for: job, inputs: $0) }
        let key = waitingKey ?? PFJobRequest.newClientKey()
        let outcome = await send(job, inputs: inputs, clientKey: key)
        if let encoded, case .failure(.offline) = outcome {
            PFJobRetryStore.add(PFQueuedJob(job: job.rawValue, inputs: encoded, clientKey: key, queuedAt: Date()))
            return .failure(.queued)
        }
        if waitingKey != nil, outcome.isSettled { PFJobRetryStore.remove(clientKey: key) }
        return outcome
    }

    /// One `POST api/app/job` with the given key.
    static func send(_ job: PFJobName, inputs: [String: Any], clientKey: String) async -> Result<PFJobSubmission, PFJobError> {
        do {
            let reply = try await PFAPI.postJob(PFJobRequest.body(job, inputs: inputs, clientKey: clientKey), timeout: job.requestTimeout)
            return PFJobReply.submission(status: reply.status, body: reply.data, retryAfter: reply.retryAfter)
        } catch {
            return .failure(PFJobError.transport(error))
        }
    }

    /// `GET api/app/job/<id>`.
    static func status(id: String) async -> Result<PFJobStatus, PFJobError> {
        do {
            let reply = try await PFAPI.jobStatus(id)
            return PFJobReply.status(status: reply.status, body: reply.data, retryAfter: reply.retryAfter)
        } catch {
            return .failure(PFJobError.transport(error))
        }
    }

    /// Follows a slow job: a look after 2 s, then every 5 s, until it is done or failed, or the job's expected time plus a margin has
    /// passed. A look that fails for a passing reason (no connection, a server hiccup, an odd answer) is not the job failing, so the wait goes on; a refusal ends it.
    static func wait(for id: String, job: PFJobName) async -> Result<Void, PFJobError> {
        let started = Date()
        var polls = 0
        while true {
            if PFJobPolling.shouldGiveUp(job: job, elapsed: Date().timeIntervalSince(started)) { return .failure(.timedOut) }
            do {
                try await Task.sleep(nanoseconds: UInt64(PFJobPolling.delay(afterPolls: polls) * 1_000_000_000))
            } catch {
                return .failure(.cancelled)
            }
            polls += 1
            switch await status(id: id) {
            case .success(let reached):
                switch reached.state {
                case .done: return .success(())
                case .failed: return .failure(.failed(reached.error))
                case .queued, .running: continue
                }
            case .failure(let failure):
                if failure.keepsWaiting { continue }
                return .failure(failure)
            }
        }
    }
}

/// The writes that got no answer, kept in UserDefaults until the server takes them, refuses them or a day has passed.
enum PFJobRetryStore {
    private static let storageKey = "noop.paceforge.jobRetryList"
    private static let lock = NSLock()

    /// The entries still worth sending.
    static func load() -> [PFQueuedJob] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([PFQueuedJob].self, from: data) else { return [] }
        return PFJobRetryList.live(entries, now: Date())
    }

    static func waitingKey(for job: PFJobName, inputs: String) -> String? {
        PFJobRetryList.key(for: job, inputs: inputs, in: load())
    }

    static func add(_ entry: PFQueuedJob) { update { PFJobRetryList.adding(entry, to: $0) } }

    static func remove(clientKey: String) { update { PFJobRetryList.removing(clientKey: clientKey, from: $0) } }

    /// Drops the entries older than a day.
    static func prune() { update { $0 } }

    private static func update(_ change: ([PFQueuedJob]) -> [PFQueuedJob]) {
        lock.lock()
        defer { lock.unlock() }
        let entries = change(load())
        if entries.isEmpty {
            UserDefaults.standard.removeObject(forKey: storageKey)
        } else if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// Sends the waiting writes again, each with the key it first went out with. The app calls it each time it comes to the foreground.
enum PFJobRetry {
    /// Returns how many the server took. A write the server refuses is dropped; one that still gets no answer, or hits a rate limit or a
    /// server hiccup, stays, and the pass stops there: the ones behind it would meet the same trouble.
    static func sendAll() async -> Int {
        guard PFAPI.isConfigured, !PFAPI.isFixture else { return 0 }
        PFJobRetryStore.prune()
        var taken = 0
        for entry in PFJobRetryStore.load() {
            guard let job = PFJobName(rawValue: entry.job), let inputs = PFJobRetryList.decodeInputs(entry.inputs) else {
                PFJobRetryStore.remove(clientKey: entry.clientKey)
                continue
            }
            let outcome = await PFJobClient.send(job, inputs: inputs, clientKey: entry.clientKey)
            if outcome.isSettled {
                PFJobRetryStore.remove(clientKey: entry.clientKey)
                if case .success = outcome { taken += 1 }
            } else {
                break
            }
        }
        return taken
    }
}

private extension Result where Success == PFJobSubmission, Failure == PFJobError {
    /// The server took the write or refused it for good, so it need not be kept.
    var isSettled: Bool {
        switch self {
        case .success: return true
        case .failure(let failure): return !failure.isRetryable
        }
    }
}

/// What a card shows about the one job it started: sending, working, done, or could not (with the reason).
@MainActor
final class PFJobTracker: ObservableObject {
    @Published private(set) var phase: PFJobPhase = .idle

    /// Runs one job to its end. A fast job is done as soon as it is sent; a slow one is followed until it is done. On success the
    /// result is the job's own `result` (empty for a slow job: its outcome is in a data file the caller reads).
    func run(_ job: PFJobName, inputs: [String: Any]) async -> Result<PFJ, PFJobError> {
        phase = .sending
        switch await PFJobClient.submit(job, inputs: inputs) {
        case .failure(let failure):
            phase = .failed(failure.message)
            return .failure(failure)
        case .success(let submission):
            if submission.state == .failed {
                phase = .failed(PFJobError.failed(nil).message)
                return .failure(.failed(nil))
            }
            if !submission.state.isFinished {
                phase = .working
                if case .failure(let failure) = await PFJobClient.wait(for: submission.id, job: job) {
                    phase = .failed(failure.message)
                    return .failure(failure)
                }
            }
            phase = .done
            return .success(submission.result)
        }
    }

    func reset() { phase = .idle }
}
