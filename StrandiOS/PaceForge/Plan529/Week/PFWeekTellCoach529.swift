import SwiftUI
import StrandDesign

/// Free-text plan requests return a dated Coach proposal. Only its Accept action changes the plan.
struct PFWeekTellCoach529: View {
    var currentDoc: PFPlanWeekDoc? = nil
    var reload: (() async -> PFPlanWeekDoc?)? = nil
    var idPrefix = "plan529-tell"
    var sessionID: String? = nil
    var targetDate: String? = nil
    var initialDraft = ""

    @ObservedObject private var model = PFUnified.model
    @ObservedObject private var proposals = PFWeekPlanStore.shared
    @State private var draft = ""
    @State private var sending = false
    @State private var reply: String?
    @State private var failure: String?
    @State private var filedIDs = Set<String>()

    private var draftKey: String {
        "noop.planTextDraft.\(sessionID ?? targetDate ?? currentDoc?.week ?? idPrefix)"
    }
    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit by text").font(PFPlanFont543.text(16, weight: .semibold))
            TextField("Describe the workout or changes you want…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3...6)
                .font(PFPlanFont543.text(14.5, weight: .regular))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NoopLook.card))
                .accessibilityIdentifier("\(idPrefix)-input")
            Button {
                Task { await send() }
            } label: {
                HStack {
                    if sending { ProgressView() }
                    Text(sending ? "Coach is reviewing…" : "Submit to Coach for review")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(PFWeekColor529.teal)
            .disabled(!canSend)
            .accessibilityIdentifier("\(idPrefix)-send")
            PFWeekSub529(text: "Review the proposed changes before accepting. Your draft stays here if sending fails.")
            if let failure {
                Text(failure).font(PFPlanFont543.text(14, weight: .regular)).foregroundStyle(PFWeekColor529.amber)
            }
            if let reply {
                Text(reply).font(PFPlanFont543.text(14, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                    .accessibilityIdentifier("\(idPrefix)-reply")
            }
            ForEach(proposals.proposals.filter { filedIDs.contains($0.id) }) { proposal in
                PFProposalView(proposal: proposal, onAsk: { draft = $0 })
            }
        }
        .containerIdentifier("\(idPrefix)-field")
        .task {
            draft = UserDefaults.standard.string(forKey: draftKey) ?? initialDraft
            await proposals.refreshIfStale()
        }
        .onChange(of: draft) { _, value in
            if value.isEmpty { UserDefaults.standard.removeObject(forKey: draftKey) }
            else { UserDefaults.standard.set(value, forKey: draftKey) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { if let reload { _ = await reload() } }
        }
    }

    @MainActor private func send() async {
        guard canSend else { return }
        guard CoachBriefScheduler.coachMasterEnabled else {
            failure = "Coach is turned off in Settings. Your draft is kept."
            return
        }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateContext: String
        if let targetDate { dateContext = "For the session on \(targetDate): " }
        else if let week = currentDoc?.week { dateContext = "For plan week \(week): " }
        else { dateContext = "" }
        let message = dateContext + typed
        guard message.count <= 2_000 else {
            failure = "Please shorten this request to fewer than 2,000 characters. Your draft is kept."
            return
        }
        sending = true
        failure = nil
        reply = nil
        filedIDs = []
        defer { sending = false }
        do {
            let response = try await PFAPI.postCoachMessage(message, sessionID: sessionID, proposalOnly: true)
            guard (200..<300).contains(response.status) else {
                failure = PFJ(data: response.data)["message"].text ?? "Request not sent. Your draft is kept."
                return
            }
            guard let requestID = PFJ(data: response.data)["id"].idString else {
                reply = "Sent. Open Coach to check the response; the server did not return a tracking identifier."
                return
            }
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == typed { draft = "" }
            reply = "Submitted. Waiting for Coach's acknowledgment and proposed changes."
            for _ in 0..<30 {
                await model.refresh()
                let coach = model.snapshot?.coach
                let turns = sessionID == nil ? (coach?.chat ?? []) : (coach?.workoutChat ?? [])
                if let answer = turns.last(where: { $0.role == "coach" && $0.requestID == requestID }) {
                    reply = answer.text
                    filedIDs = Set(answer.proposalIDs)
                    await proposals.refresh()
                    return
                }
                if case .success(let job) = await PFJobClient.status(id: requestID) {
                    if job.state == .failed {
                        failure = PFJobError.failed(job.error).message
                        reply = nil
                        if draft.isEmpty { draft = typed }
                        return
                    }
                    if job.state == .done {
                        reply = "Coach finished. Refresh Coach or plan proposals to read the response."
                        await model.refresh()
                        await proposals.refresh()
                        return
                    }
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
            reply = "Submitted. The response is not available here yet; check Coach or plan proposals."
        } catch is CancellationError {
            reply = "Your submitted request remains with Coach."
        } catch {
            failure = "Couldn't send. Your draft is kept. \(PFAPI.failureDetail(error))"
        }
    }

    /// The days of the week document whose workouts differ: one added, dropped, moved, renamed, resized or given another state.
    static func changedDays(before: PFPlanWeekDoc?, after: PFPlanWeekDoc) -> [String] {
        guard let before else { return [] }
        func signatures(_ doc: PFPlanWeekDoc) -> [String: [String]] {
            var out: [String: [String]] = [:]
            for day in doc.days ?? [] {
                guard let date = day.date else { continue }
                out[date] = (day.items ?? []).map { item in
                    [item.sessionId ?? "", item.title ?? "", item.kind ?? "", item.status ?? "",
                     String(item.minutes ?? 0), item.effort ?? ""].joined(separator: "|")
                }.sorted()
            }
            return out
        }
        let old = signatures(before)
        let new = signatures(after)
        return Set(old.keys).union(new.keys).filter { (old[$0] ?? []) != (new[$0] ?? []) }.sorted()
    }
}
