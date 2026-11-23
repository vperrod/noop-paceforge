import SwiftUI
import UIKit
import StrandDesign

/// W2 (build 543, drawings 3.2, 3.3, 3.6, 3.7): one session on one screen. The header with its badges and the same three actions in the same
/// place (Edit, Note, ···), what to do as numbered pieces, what you did against what was asked, the assessment, and the notes thread with the
/// composer. Why this session, the long briefing and the last time are one tap further down.
struct PFSessionSheet529: View {
    let week: String
    let sessionId: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var router: NavRouter
    @StateObject private var store: PFDocStore529<PFPlanWeekDoc>
    @ObservedObject private var model = PFUnified.model
    @State private var results: PFResultsTarget529?
    @State private var swap: PFSwapTarget529?
    @State private var describeTarget: PFDescribeTarget529?
    @State private var execution: PFSessionExecution543?
    @State private var thread: PFSessionThread543?
    @State private var showsMore = false
    @State private var showsWhy = false
    @State private var showsWords = false
    @State private var noteDraft = ""
    @State private var isSendingNote = false
    @State private var noteStatus: String?
    @State private var localNotes: [String] = []
    @State private var isWatchingReassess = false
    @State private var watchTask: Task<Void, Never>?
    @FocusState private var noteFocused: Bool
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

    private var describeBinding: Binding<Bool> {
        Binding(get: { describeTarget != nil }, set: { if !$0 { describeTarget = nil } })
    }

    private var noteKey: String { "noop.planNoteDraft.\(sessionId)" }

    var body: some View {
        ScrollViewReader { proxy in
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
                            content(day: found.day, item: found.item, proxy: proxy)
                        } else {
                            PFWeekState529(kind: .empty, message: "This session is no longer on your plan.")
                        }
                    }
                }
                .padding(.horizontal, NoopLook.Metric.screenInset)
                .padding(.top, 8)
                .padding(.bottom, NoopMetrics.tabBarClearance)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .lookScreenBackground()
        .navigationTitle(found?.item.title ?? "Session")
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier("plan529-session")
        // One sheet per view: two sheet modifiers on the same view leave only the last one working.
        .background { Color.clear.pfResultsSheet529($results) }
        .background {
            Color.clear.sheet(item: $swap) { target in PFChangeWorkoutSheet529(target: target) }
        }
        .background {
            Color.clear.sheet(isPresented: describeBinding) {
                if let target = describeTarget {
                    PFSessionDescriptionSheet529(target: target) { sent in
                        noteStatus = sent
                        UIAccessibility.post(notification: .announcement, argument: sent)
                        startWatching()
                    }
                }
            }
        }
        .task {
            noteDraft = UserDefaults.standard.string(forKey: noteKey) ?? ""
            await store.refreshIfStale()
            await model.refreshIfStale()
            await loadExtras()
        }
        .onChange(of: noteDraft) { _, value in
            if value.isEmpty { UserDefaults.standard.removeObject(forKey: noteKey) } else { UserDefaults.standard.set(value, forKey: noteKey) }
        }
        .onChange(of: store.state) { _, _ in Task { await loadExtras() } }
        .onReceive(NotificationCenter.default.publisher(for: .pfPlan529Changed)) { _ in
            Task { await store.refresh() }
        }
        .onDisappear {
            textEditTask?.cancel()
            textEditTask = nil
            watchTask?.cancel()
            watchTask = nil
        }
    }

    // MARK: Content

    @ViewBuilder private func content(day: PFPlanWeekDoc.Day, item: PFPlanWeekDoc.Item, proxy: ScrollViewProxy) -> some View {
        let date = day.date ?? ""
        let isDone = PFPlanRow543.isDone(item)
        VStack(alignment: .leading, spacing: 12) {
            header(item, date: date, day: day, isDone: isDone, proxy: proxy)
            PFCoachSessionNote542(item: item, idPrefix: "plan529-sheet-coach", showsMustLine: false)
            if !isDone { PFWatchChip529(sessionID: item.sessionId) }
            if !isDone || execution?.isAvailable != true { PFWhatToDoCard543(item: item) }
            if !isDone, item.kind == nil || item.kind == "session", let id = item.sessionId {
                PFSessionEffortCard544(item: item, sessionID: id)
            }
            if isDone { PFWhatYouDidCard543(item: item, execution: execution) }
            if isDone || isReassessing(item) {
                PFAssessmentCard543(item: item, thread: thread, isReassessing: isReassessing(item),
                                    openResults: item.activityId.map { id in { results = PFResultsTarget529(id: id, title: item.title, date: date) } })
            }
            if item.sessionId != nil {
                PFNotesCard543(thread: thread, localNotes: localNotes, draft: $noteDraft, isSending: isSendingNote, status: noteStatus,
                               sendTitle: canReassess(item) ? PFSessionText543.sendAndReassess : PFSessionText543.sendNote,
                               canSend: !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               isFocused: $noteFocused, onSend: { Task { await sendNote(item) } })
                    .id("plan529-composer")
            }
            why(item)
            more(item, date: date)
            if !isDone, let id = item.sessionId { wordsEdit(sessionID: id) }
        }
    }

    private func isReassessing(_ item: PFPlanWeekDoc.Item) -> Bool {
        thread?.isReassessing == true || isWatchingReassess || (PFPlanRow543.isDone(item) && item.review?.state == "pending")
    }

    /// A finished workout with a recording the analysis can read again: the note reassesses it.
    private func canReassess(_ item: PFPlanWeekDoc.Item) -> Bool {
        PFPlanRow543.isDone(item) && reassessActivityID(item) != nil
    }

    private func reassessActivityID(_ item: PFPlanWeekDoc.Item) -> String? {
        guard let id = item.activityId, !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return id
    }

    // MARK: Header

    private func header(_ item: PFPlanWeekDoc.Item, date: String, day: PFPlanWeekDoc.Day, isDone: Bool, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.title ?? "")
                .font(PFPlanFont543.text(22, weight: .bold))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("plan529-session-title")
            Text(dateLine(item, date: date))
                .font(PFPlanFont543.text(16, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan529-session-date")
            PFPlanBadgeRow543(badges: PFPlanRow543.badges(item))
            if let id = item.sessionId, item.kind == nil || item.kind == "session" {
                PFSessionActionBar529(
                    target: PFSessionTarget529(sessionId: id, title: item.title ?? "", date: date, status: item.status ?? "planned",
                                               isToday: store.doc?.strip?.first(where: { $0.date == date })?.today == true,
                                               minutes: item.minutes, rpe: item.rpe, isMandatory: item.mandatory == true),
                    menu: PFSessionMenu543.items(status: item.status ?? "planned", isOptional: item.optional == true, isDone: isDone),
                    idPrefix: "plan529-sheet",
                    onChangeWorkout: { swap = PFSwapTarget529(week: week, date: date, sessionId: id, title: item.title, minutes: item.minutes) },
                    onAskCoach: { askCoach(item, date: date) },
                    onJudged: { openJudged(item, date: date, proxy: proxy) },
                    leading: {
                        PFWeekButton529(title: "Edit", identifier: "plan529-sheet-describe") {
                            describeTarget = PFDescribeTarget529(item: item, sessionID: id)
                        }
                        PFWeekButton529(title: "Note", identifier: "plan529-sheet-note") {
                            withAnimation { proxy.scrollTo("plan529-composer", anchor: .center) }
                            noteFocused = true
                        }
                    })
            }
        }
        .containerIdentifier("plan529-session-header")
    }

    /// "Mon 23 Nov \u{00B7} 54 min \u{00B7} Easy \u{00B7} 3 of 10".
    private func dateLine(_ item: PFPlanWeekDoc.Item, date: String) -> String {
        var parts: [String] = []
        if !date.isEmpty { parts.append(PFFormat.dayTitle(date)) }
        if let minutes = item.minutes { parts.append("\(minutes) min") }
        if let effort = item.effort {
            let word = PFFormat.capitalized(effort)
            parts.append(hiding.text(item.rpe.map { "\(word) \u{00B7} \($0) of 10" } ?? word))
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    private func openJudged(_ item: PFPlanWeekDoc.Item, date: String, proxy: ScrollViewProxy) {
        if PFPlanRow543.isDone(item), let id = item.activityId {
            results = PFResultsTarget529(id: id, title: item.title, date: date)
        } else {
            withAnimation { showsMore = true }
            withAnimation { proxy.scrollTo("plan529-more", anchor: .top) }
        }
    }

    // MARK: Why, more and last time

    /// The old blocks (why this session, where it sits, how hard, if you wake up red, after), one tap away so the coach's words are not repeated.
    @ViewBuilder private func why(_ item: PFPlanWeekDoc.Item) -> some View {
        let rows: [(String, String?)] = [("Why this session", item.why), ("Where it sits", item.where), ("How hard", item.howHard),
                                         ("If you wake up red", item.ifRed), ("After", PFPlanRow543.isDone(item) ? nil : item.after)]
        let present = rows.filter { ($0.1 ?? "").isEmpty == false }
        if !present.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { showsWhy.toggle() } } label: {
                    row(title: "Why this session", sub: nil, symbol: showsWhy ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsWhy ? "Expanded" : "Collapsed")
                .accessibilityIdentifier("plan529-session-why-toggle")
                if showsWhy {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(present.indices, id: \.self) { index in
                            PFWeekLine529(label: present[index].0, text: present[index].1 ?? "",
                                          tint: present[index].0 == "If you wake up red" ? PFWeekColor529.red : NoopLook.textSecondary)
                        }
                    }
                    .padding(.top, 8)
                    .accessibilityIdentifier("plan529-session-why")
                }
            }
            .pfWeekCard()
        }
    }

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
            .id("plan529-more")
        }
    }

    private func row(title: String, sub: String?, symbol: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(PFPlanFont543.text(16, weight: .medium))
                    .foregroundStyle(NoopLook.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let sub { PFWeekSub529(text: sub) }
            }
            Spacer(minLength: 8)
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NoopLook.textSecondary)
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

    // MARK: Server reads

    /// What the session screen adds to the week document: the asked-against-did table of a finished workout and the notes thread. A server that
    /// does not serve them yet leaves both nil and the screen falls back to the week document.
    @MainActor private func loadExtras() async {
        guard let item = found?.item else { return }
        if PFPlanRow543.isDone(item), let id = item.activityId, PFJobInputs.sessionID(id) != nil {
            let fetched = await PFAPI.fetchDoc("api/session-execution?activity_id=\(id)")
            execution = PFSessionExecution543.parse(fetched.data)
        } else {
            execution = nil
        }
        let fetched = await PFAPI.fetchDoc("api/session-thread?session_id=\(sessionId)")
        thread = PFSessionThread543.parse(fetched.data)
    }

    // MARK: The note

    /// Sends the note to the Coach on this session; on a finished workout with a recording it also asks for the reassessment.
    @MainActor private func sendNote(_ item: PFPlanWeekDoc.Item) async {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSendingNote else { return }
        guard CoachBriefScheduler.coachMasterEnabled else {
            noteStatus = "Coach is turned off in Settings. Your note is kept here."
            return
        }
        guard text.count <= 2_000 else {
            noteStatus = "Use 2,000 characters or fewer. Your note is kept."
            return
        }
        isSendingNote = true
        defer { isSendingNote = false }
        do {
            let reassess = canReassess(item) ? reassessActivityID(item) : nil
            let reply = try await PFAPI.postCoachMessage(text, sessionID: sessionId, reassessActivityID: reassess)
            guard (200..<300).contains(reply.status) else {
                noteStatus = PFJ(data: reply.data)["message"].text ?? "The note was not sent. Your note is kept."
                return
            }
            localNotes.append(text)
            noteDraft = ""
            let body = PFJ(data: reply.data)
            if reassess != nil {
                noteStatus = body["reassessment_error"].text ?? "Sent. The Coach is reassessing this workout."
            } else {
                noteStatus = "Sent. The Coach reads it and may answer here."
            }
            UIAccessibility.post(notification: .announcement, argument: noteStatus ?? "Sent")
            if reassess != nil, body["reassessment_error"].text == nil { startWatching() } else { Task { await loadExtras() } }
        } catch {
            noteStatus = "Could not send that. \(PFAPI.failureDetail(error)) Your note is kept."
        }
    }

    /// After a note or a saved edit on a finished workout: read the thread and the week again every few seconds until the Coach is done.
    private func startWatching() {
        watchTask?.cancel()
        isWatchingReassess = true
        watchTask = Task { @MainActor in
            for round in 0..<20 {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                await loadExtras()
                await store.refresh()
                if round >= 1, thread?.isReassessing != true, found?.item.review?.state != "pending" { break }
            }
            isWatchingReassess = false
            await model.refresh()
        }
    }

    // MARK: Change it in my words

    @ViewBuilder private func wordsEdit(sessionID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { showsWords.toggle() } } label: {
                row(title: "Ask the Coach to change this workout", sub: nil, symbol: showsWords ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(.plain)
            .accessibilityValue(showsWords ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("plan529-session-words-toggle")
            if showsWords { textEdit(sessionID: sessionID) }
        }
        .pfWeekCard()
    }

    private func textEdit(sessionID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Change this workout in your words")
                .font(PFPlanFont543.text(16, weight: .semibold))
                .foregroundStyle(NoopLook.textPrimary)
            Text("Describe the replacement. Coach will review it and file a proposed change for you to accept.")
                .font(PFPlanFont543.text(15, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("e.g. 40 minutes easy with 6 relaxed strides", text: $textEditDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .font(PFPlanFont543.text(16, weight: .regular))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NoopLook.row))
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
                    Text(textEditSending ? "Waiting for Coach\u{2026}" : "Send to Coach")
                        .font(PFPlanFont543.text(16, weight: .semibold))
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
                    .font(PFPlanFont543.text(15, weight: .regular))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan529-session-text-edit-status")
            }
        }
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
                        : "Coach proposed: \(proposals.joined(separator: ", ")). Review it under Needs you to decide."
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
}

#if DEBUG
#Preview("Pieces at the largest text size") {
    ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            PFWhatToDoCard543(item: PFPlanWeekDoc.Item(
                kind: "session", sessionId: "s-1", title: "Run test", minutes: 54, status: "planned",
                pieces: [PFPlanWeekDoc.Piece(n: 1, label: "Warm-up 2 km", text: nil, effort: "easy", band: "Heart rate under Z2 \u{00B7} from your zones"),
                         PFPlanWeekDoc.Piece(n: 2, label: "Test 5 km all out", text: "No upper limit. Hold it.", effort: "all_out", band: nil),
                         PFPlanWeekDoc.Piece(n: 3, label: "Cooldown 2 km", text: nil, effort: "easy", band: nil)]))
            PFPlanBadgeRow543(badges: PFPlanRow543.badges(PFPlanWeekDoc.Item(
                kind: "session", title: "Run test", status: "planned", coachAssigned: true, requiredThisWeek: true,
                overlap: PFPlanWeekDoc.Overlap(with: ["Cardio Class"], reason: nil), needsYou: true)))
        }
        .padding(16)
    }
    .lookScreenBackground()
    // Check every screen of the Plan at the largest setting: rows wrap, nothing is cut off, every button stays 44 points tall.
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
