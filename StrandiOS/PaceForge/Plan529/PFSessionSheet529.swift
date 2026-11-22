import SwiftUI
import UIKit
import StrandDesign

/// W2, one session of a week: the actions at the top (Make it easier, Move, Skip, Make optional, Change workout, Ask the coach), five short
/// blocks (why, where it sits, how hard, what to do, what to do on a bad morning), and "More about this session" with the long briefing and
/// the session breakdown the old session detail had. A "last time" row opens the previous matching workout with the coach's review.
struct PFSessionSheet529: View {
    let week: String
    let sessionId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>
    @ObservedObject private var model = PFUnified.model
    @State private var results: PFResultsTarget529?
    @State private var swap: PFSwapTarget529?
    @State private var showsMore = false
    @State private var textEditDraft = ""
    @State private var textEditSending = false
    @State private var textEditStatus: String?
    @State private var textEditTask: Task<Void, Never>?
    private let hiding = PFHiding()

    init(week: String, sessionId: String) {
        self.week = week
        self.sessionId = sessionId
        _store = StateObject(wrappedValue: PFDocStore529<PFPlanWeekDoc>(path: PFDocPath529.week(week)))
    }

    private var found: (day: PFPlanWeekDoc.Day, item: PFPlanWeekDoc.Item)? {
        guard let doc = store.doc else { return nil }
        for day in doc.days ?? [] {
            if let item = (day.items ?? []).first(where: { $0.sessionId == sessionId }) { return (day, item) }
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                switch store.state {
                case .loading:
                    PFWeekState529(kind: .loading, message: "Loading the session")
                case .empty:
                    PFWeekState529(kind: .empty, message: "This session is not on your plan.")
                case .failed:
                    PFWeekState529(kind: .failed, message: "The session could not be loaded.", retry: { Task { await store.refresh() } })
                case .loaded:
                    if let found {
                        content(day: found.day, item: found.item)
                    } else {
                        PFWeekState529(kind: .empty, message: "This session is no longer on your plan.")
                    }
                }
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle(found?.item.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("plan529-session")
        // One sheet per view: two sheet modifiers on the same view leave only the last one working.
        .background { Color.clear.pfResultsSheet529($results) }
        .sheet(item: $swap) { target in PFChangeWorkoutSheet529(target: target) }
        .task {
            await store.refreshIfStale()
            await model.refreshIfStale()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { await store.refresh() }
        }
        .onDisappear {
            textEditTask?.cancel()
            textEditTask = nil
        }
    }

    // MARK: Content

    @ViewBuilder private func content(day: PFPlanWeekDoc.Day, item: PFPlanWeekDoc.Item) -> some View {
        let date = day.date ?? ""
        let isDone = ["done", "partial"].contains(item.status ?? "")
        VStack(alignment: .leading, spacing: 12) {
            Text(item.title ?? "")
                .font(LookFont.text(22, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .accessibilityIdentifier("plan529-session-title")
            PFWeekPills529(pills: pills(item, date: date))
            if !isDone { PFWatchChip529(sessionID: item.sessionId) }
            if isDone, let activityId = item.activityId {
                PFWeekButton529(title: "Open the results", isProminent: true, identifier: "plan529-session-results") {
                    results = PFResultsTarget529(id: activityId, title: item.title, date: date)
                }
            } else if let id = item.sessionId {
                PFSessionActionBar529(target: PFSessionTarget529(sessionId: id, title: item.title ?? "", date: date,
                                                                 status: item.status ?? "planned", isToday: store.doc?.strip?.first(where: { $0.date == date })?.today == true,
                                                                 minutes: item.minutes, rpe: item.rpe),
                                      actions: PFSessionAction529.forSession(status: item.status ?? "planned",
                                                                             isOptional: item.optional == true, includesAskCoach: true),
                                      idPrefix: "plan529-sheet",
                                      onChangeWorkout: {
                                          swap = PFSwapTarget529(week: week, date: date, sessionId: id, title: item.title, minutes: item.minutes)
                                      },
                                      onAskCoach: { askCoach(item, date: date) })
            }
            if !isDone, let id = item.sessionId {
                textEdit(sessionID: id)
            }
            blocks(item)
            more(item, date: date)
        }
    }

    private func textEdit(sessionID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change this workout in your words")
                .font(LookFont.text(15, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Text("Describe the replacement. Coach will review it and file a proposed change for you to accept.")
                .font(LookFont.text(12.5, weight: .regular))
                .foregroundStyle(NoopLook.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("e.g. 40 minutes easy with 6 relaxed strides", text: $textEditDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .font(LookFont.text(14, weight: .regular))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.card))
                .accessibilityLabel("Describe the replacement workout")
                .accessibilityIdentifier("plan529-session-text-edit-input")
                .onChange(of: textEditDraft) { _, value in
                    if value.count > 1_600 { textEditDraft = String(value.prefix(1_600)) }
                }
            Button {
                textEditTask = Task { await sendTextEdit(sessionID: sessionID) }
            } label: {
                HStack(spacing: 8) {
                    if textEditSending { ProgressView().tint(NoopLook.textPrimary) }
                    Text(textEditSending ? "Waiting for Coach…" : "Send to Coach")
                        .font(LookFont.text(14, weight: .semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(NoopLook.textPrimary)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(PFWeekColor529.teal.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .disabled(textEditSending || !CoachBriefScheduler.coachMasterEnabled
                      || textEditDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("plan529-session-text-edit-send")
            if let textEditStatus {
                Text(textEditStatus)
                    .font(LookFont.text(12.5, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-session-text-edit-status")
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-session-text-edit")
    }

    @MainActor private func sendTextEdit(sessionID: String) async {
        let request = textEditDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !textEditSending else { return }
        guard CoachBriefScheduler.coachMasterEnabled else {
            textEditStatus = "Coach is turned off in Settings."
            return
        }
        let before = model.snapshot
        let previousCoachTurn = before?.coach.chat.last(where: { $0.role == "coach" })?.ts
        let needsBefore = before?.needsYou ?? []
        textEditSending = true
        textEditStatus = nil
        defer { textEditSending = false }
        do {
            let message = "Replace this workout with: \(request)"
            let result = try await PFAPI.postCoachMessage(message, sessionID: sessionID)
            guard (200..<300).contains(result.status) else {
                setTextEditStatus(PFJ(data: result.data)["message"].text
                                  ?? "Coach refused the request (HTTP \(result.status)).")
                return
            }
            textEditDraft = ""
            setTextEditStatus("Sent. Your booked workout stays unchanged until you accept a Coach proposal.")
            for _ in 0..<30 {
                guard !Task.isCancelled else { return }
                await model.refresh()
                guard !Task.isCancelled else { return }
                if let reply = PFCoachInstruction.reply(in: model.snapshot?.coach.chat ?? [], after: previousCoachTurn) {
                    let proposals = PFCoachInstruction.newProposals(before: needsBefore, after: model.snapshot?.needsYou ?? [])
                    let status = proposals.isEmpty
                        ? "Coach replied: \(reply) Your booked workout stays unchanged until you accept a Coach proposal."
                        : "Coach proposed: \(proposals.joined(separator: ", ")). Review it under Changes to decide."
                    setTextEditStatus(status)
                    NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
                    await store.refresh()
                    return
                }
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { return }
            }
            setTextEditStatus("Sent to Coach. Your booked workout is unchanged while it prepares a reply.")
        } catch {
            guard !Task.isCancelled else { return }
            setTextEditStatus("Couldn't send that. \(PFAPI.failureDetail(error))")
        }
    }

    @MainActor private func setTextEditStatus(_ status: String) {
        textEditStatus = status
        UIAccessibility.post(notification: .announcement, argument: status)
    }

    private func pills(_ item: PFPlanWeekDoc.Item, date: String) -> [(text: String, color: Color)] {
        var out: [(text: String, color: Color)] = [(PFFormat.dayTitle(date), NoopLook.textTertiary)]
        if let minutes = item.minutes { out.append(("\(minutes) min", NoopLook.textTertiary)) }
        if let effort = item.effort {
            let word = PFFormat.capitalized(effort)
            out.append((hiding.text(item.rpe.map { "\(word) \u{00B7} \($0) of 10" } ?? word), PFWeekColor529.effort(effort)))
        }
        for pill in item.pills ?? [] { out.append((pill, NoopLook.textTertiary)) }
        return out
    }

    private func blocks(_ item: PFPlanWeekDoc.Item) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let first = [("Why this session", item.why), ("Where it sits", item.where)]
            let second = [("How hard", item.howHard), ("Do", item.do), ("If you wake up red", item.ifRed), ("After", item.after)]
            card(first, id: "plan529-session-why")
            card(second, id: "plan529-session-do")
        }
    }

    @ViewBuilder private func card(_ rows: [(String, String?)], id: String) -> some View {
        let present = rows.filter { ($0.1 ?? "").isEmpty == false }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(present.indices, id: \.self) { index in
                    PFWeekLine529(label: present[index].0, text: present[index].1 ?? "",
                                  tint: present[index].0 == "If you wake up red" ? PFWeekColor529.red : NoopLook.textTertiary)
                }
            }
            .pfWeekCard()
            .containerIdentifier(id)
        }
    }

    // MARK: More and last time

    @ViewBuilder private func more(_ item: PFPlanWeekDoc.Item, date: String) -> some View {
        let planned = item.sessionId.flatMap { id in model.snapshot.flatMap { PFWeekLookup529.plannedWorkout(sessionId: id, in: $0) } }
        let last = lastTime(item, date: date)
        if planned != nil || last != nil {
            VStack(alignment: .leading, spacing: 0) {
                if let planned {
                    Button { withAnimation(.easeInOut(duration: 0.2)) { showsMore.toggle() } } label: {
                        row(title: "More about this session", sub: nil, symbol: showsMore ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsMore ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("plan529-session-more")
                    if showsMore {
                        PFWorkoutDetail(workout: planned, showsEdits: false)
                            .padding(.top, 8)
                            .accessibilityIdentifier("plan529-session-detail")
                    }
                }
                if planned != nil, last != nil { Divider().overlay(NoopLook.divider) }
                if let last {
                    Button { results = PFResultsTarget529(id: last.id, title: last.title, date: last.date) } label: {
                        row(title: "Last time: \(last.title), \(PFFormat.shortDate(last.date))",
                            sub: "Opens that workout with the coach's review", symbol: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan529-session-last")
                }
            }
            .pfWeekCard()
        }
    }

    private func row(title: String, sub: String?, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LookFont.text(15, weight: .medium)).foregroundStyle(NoopLook.textPrimary)
                if let sub { PFWeekSub529(text: sub) }
            }
            Spacer(minLength: 8)
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NoopLook.textTertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The previous matching workout: the one the server names, else the latest recording of the same name before this day.
    private func lastTime(_ item: PFPlanWeekDoc.Item, date: String) -> (id: String, title: String, date: String)? {
        if let named = item.lastTime, let id = named.activityId {
            return (id, named.title ?? item.title ?? "Workout", named.date ?? "")
        }
        guard let snapshot = model.snapshot, let title = item.title,
              let activity = PFWeekLookup529.lastTime(title: title, before: date, in: snapshot) else { return nil }
        return (activity.id, activity.name ?? title, String((activity.startTime ?? "").prefix(10)))
    }

    private func askCoach(_ item: PFPlanWeekDoc.Item, date: String) {
        PFChatPrefill.shared.text = "About \(item.title ?? "this workout") on \(PFFormat.dayTitle(date)): why is it in my plan, and what happens if I change it?"
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.openCoach() }
    }
}
