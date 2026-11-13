import SwiftUI
import StrandDesign

/// What the one Coach composer does with the text: asks the coach a question (the chat) or gives it an order to change the plan.
enum PFComposerMode: String, CaseIterable, Identifiable {
    case question, changePlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .question: return "Question"
        case .changePlan: return "Change my plan"
        }
    }

    var placeholder: String {
        switch self {
        case .question: return "Ask your coach"
        case .changePlan: return "What should change?"
        }
    }
}

/// The one free-text input of the Coach, at the top under today's read. A Question goes to the chat; Change my plan goes to PaceForge's
/// coach job (`coach`, a slow job: half a minute to a few minutes), which turns an order in plain words (move my long run to Sunday, I'm
/// sick, waist 92) into plan edits, a niggle, an easy week or a tape entry. Its result is the list of days whose sessions changed, each
/// a link to that day in Plan, then whatever it filed to be looked at.
struct PFCoachComposer: View {
    let snapshot: PFSnapshot
    @EnvironmentObject private var model: PFModel
    @EnvironmentObject private var noopCoach: AICoachEngine
    @ObservedObject private var prefill = PFChatPrefill.shared
    @StateObject private var tracker = PFJobTracker()
    @State private var mode = PFComposerMode.question
    @State private var draft = ""
    @State private var sending = false
    @State private var chatStatus: String?
    @State private var reply: String?
    @State private var filed: [String] = []
    @State private var changedDays: [String] = []

    private static let bullet = "\u{2022} "
    private static let shownTurns = 4

    private var isBusy: Bool { sending || tracker.phase == .sending || tracker.phase == .working }

    private var canSend: Bool {
        switch mode {
        case .question:
            return !isBusy && CoachBriefScheduler.coachMasterEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .changePlan:
            return !isBusy && PFJobInputs.coach(draft) != nil
        }
    }

    var body: some View {
        PFCard("Ask your coach", icon: "bubble.left.and.bubble.right") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("What to send", selection: $mode) {
                    ForEach(PFComposerMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("pf-composer-mode")
                HStack(spacing: 10) {
                    TextField(mode.placeholder, text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
                        .accessibilityIdentifier("pf-chat-input")
                    Button {
                        Task { await send() }
                    } label: {
                        if isBusy {
                            ProgressView().tint(StrandPalette.accent).frame(width: 44, height: 44)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(StrandFont.title2)
                                .foregroundStyle(StrandPalette.accent)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel(mode == .question ? "Send message to Coach" : "Send the change to Coach")
                    .accessibilityIdentifier("pf-chat-send")
                }
                if mode == .question { questionOutput } else { changeOutput }
            }
        }
        .id(PFChatPrefill.scrollID)
        .containerIdentifier("pf-coach-composer")
        .task(id: prefill.text) {
            // "Ask the coach about this" fills the box and leaves the sending to the athlete.
            guard let text = prefill.text, !text.isEmpty else { return }
            prefill.text = nil
            mode = .question
            draft = text
        }
        .task(id: noopCoach.pendingPrompt) {
            guard let prompt = noopCoach.pendingPrompt, !prompt.isEmpty else { return }
            let sessionID = noopCoach.pendingSessionID
            noopCoach.pendingPrompt = nil
            noopCoach.pendingSessionID = nil
            mode = .question
            await sendMessage(prompt, sessionID: sessionID)
        }
    }

    private func send() async {
        switch mode {
        case .question: await sendMessage()
        case .changePlan: await sendChange()
        }
    }

    // MARK: Question

    @ViewBuilder private var questionOutput: some View {
        ForEach(Array(snapshot.coach.chat.suffix(Self.shownTurns))) { PFChatBubble(turn: $0) }
        if let chatStatus {
            Text(chatStatus)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pf-chat-status")
        } else {
            Text("Your Coach uses your latest synced PaceForge and NOOP data.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @MainActor private func sendMessage(_ suppliedMessage: String? = nil, sessionID: String? = nil) async {
        let message = (suppliedMessage ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }
        guard CoachBriefScheduler.coachMasterEnabled else {
            chatStatus = "Coach is turned off in Settings."
            return
        }
        let previousCoachTurn = snapshot.coach.chat.last(where: { $0.role == "coach" })?.ts
        sending = true
        chatStatus = nil
        defer { sending = false }
        do {
            let result = try await PFAPI.postCoachMessage(message, sessionID: sessionID)
            guard (200..<300).contains(result.status) else {
                chatStatus = PFJ(data: result.data)["message"].text
                    ?? "The server refused the message (HTTP \(result.status))."
                return
            }
            draft = ""
            await model.refresh()
            for _ in 0..<30 {
                if let reply = model.snapshot?.coach.chat.last(where: { $0.role == "coach" }),
                   reply.ts != previousCoachTurn {
                    return
                }
                try await Task.sleep(nanoseconds: 3_000_000_000)
                await model.refresh()
            }
            chatStatus = "Your message was sent; the Coach is still working. Refresh to check for the reply."
        } catch {
            chatStatus = "Couldn't send your message. \(PFAPI.failureDetail(error))"
        }
    }

    // MARK: Change my plan

    @ViewBuilder private var changeOutput: some View {
        switch tracker.phase {
        case .sending, .working:
            HStack(spacing: 8) {
                ProgressView()
                Text("Working on it. This can take a few minutes.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .done:
            outcome
        case .idle:
            Text("Give an order in plain words, like move my long run to Sunday. The coach changes the plan and lists the days it touched.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var outcome: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reply {
                Text(reply)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pf-tell-coach-reply")
            } else {
                Text("Done.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textSecondary)
            }
            if changedDays.isEmpty {
                Text("No day of the plan changed.")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                    .accessibilityIdentifier("pf-changed-days-none")
            } else {
                Text("Changed days").strandOverline()
                ForEach(changedDays, id: \.self) { day in
                    NavigationLink(value: TabRoute.planDay(day)) {
                        HStack {
                            Text(PFFormat.dayTitle(day))
                                .font(StrandFont.subhead.weight(.semibold))
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(StrandFont.caption.weight(.semibold))
                                .foregroundStyle(StrandPalette.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pf-changed-day-\(day)")
                }
            }
            if !filed.isEmpty {
                Text("The coach filed these for you to look at:")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                ForEach(filed, id: \.self) { title in
                    Text(Self.bullet + title)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @MainActor private func sendChange() async {
        guard let inputs = PFJobInputs.coach(draft) else { return }
        let previous = model.snapshot?.coach.chat.last(where: { $0.role == "coach" })?.ts
        let before = model.snapshot?.needsYou ?? []
        let weeksBefore = model.snapshot?.weeks ?? snapshot.weeks
        reply = nil
        filed = []
        changedDays = []
        guard case .success = await tracker.run(.coach, inputs: inputs) else { return }
        draft = ""
        await model.refresh()
        reply = PFCoachInstruction.reply(in: model.snapshot?.coach.chat ?? [], after: previous)
        filed = PFCoachInstruction.newProposals(before: before, after: model.snapshot?.needsYou ?? [])
        changedDays = PFPlanDiff.changedDays(before: weeksBefore, after: model.snapshot?.weeks ?? [])
    }
}

struct PFChatBubble: View {
    let turn: PFChatTurn

    private var isAthlete: Bool { turn.role == "athlete" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if isAthlete { Spacer(minLength: 40) }
                Text(turn.text)
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isAthlete ? StrandPalette.accent.opacity(0.22) : StrandPalette.surfaceInset)
                    )
                if !isAthlete { Spacer(minLength: 40) }
            }
            if !isAthlete, !turn.ts.isEmpty { PFRateRow(kind: "chat", id: turn.ts) }
        }
    }
}
