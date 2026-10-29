import SwiftUI

// The network half of the job door (the pure half, PaceForgeJob.swift, is unit-tested): submit a job, follow a slow one, and a small
// observable that a view shows while its job is in flight.

enum PFJobClient {
    /// `POST api/app/job`. A fast job has run inline by the time this returns (`state` done, its `result` filled); a slow one is queued.
    static func submit(_ job: PFJobName, inputs: [String: Any]) async -> Result<PFJobSubmission, PFJobError> {
        do {
            let reply = try await PFAPI.postJob(PFJobRequest.body(job, inputs: inputs), timeout: job.requestTimeout)
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
    /// passed. A request that drops while waiting is not the job failing, so the wait goes on; a refusal ends it.
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
                if failure == .offline { continue }
                return .failure(failure)
            }
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
