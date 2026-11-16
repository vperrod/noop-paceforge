import SwiftUI
import StrandDesign

// The parts the Week screens share (W1 to W5 and R1): the colours of the approved drawings, the tile every block sits in, the pills and
// buttons, and the one place a proposal is accepted or kept. Written for the PaceForge look (NoopLook / LookFont), no new visual language.

enum PFWeekColor529 {
    static let teal = Color(hex: "#00F19F")
    static let amber = Color(hex: "#FFB23D")
    static let red = Color(hex: "#FF6B7F")
    static let blue = Color(hex: "#7AB8FF")

    /// easy teal, moderate blue, hard amber, race red.
    static func effort(_ effort: String?) -> Color {
        switch effort ?? "" {
        case "hard": return amber
        case "moderate": return blue
        case "easy": return teal
        case "race": return red
        default: return NoopLook.textTertiary
        }
    }

    /// The band words of the nights series.
    static func band(_ band: String?) -> Color {
        switch band ?? "" {
        case "green": return teal
        case "amber": return amber
        case "red": return red
        default: return NoopLook.textTertiary
        }
    }
}

extension Notification.Name {
    /// Posted after anything changed the plan (a proposal answered, a session edited): every Week page and sheet reads its document again.
    static let pfPlan529Changed = Notification.Name("pf.plan529.changed")
}

extension View {
    /// The tile every block of the Week screens sits in.
    func pfWeekCard() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }
}

struct PFWeekOverline529: View {
    let text: String

    var body: some View {
        Text(text)
            .lookCaps(10.5, weight: .semibold)
            .foregroundStyle(NoopLook.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A small grey line under a block.
struct PFWeekSub529: View {
    let text: String
    private let hiding = PFHiding()

    var body: some View {
        Text(hiding.text(text))
            .font(LookFont.text(12, weight: .regular))
            .foregroundStyle(NoopLook.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Body text of a card.
struct PFWeekBody529: View {
    let text: String
    private let hiding = PFHiding()

    var body: some View {
        Text(hiding.text(text))
            .font(LookFont.text(14.5, weight: .regular))
            .foregroundStyle(NoopLook.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// An overline label and its text ("Why", "How hard", "Do", "If you wake up red").
struct PFWeekLine529: View {
    let label: String
    let text: String
    var tint: Color = NoopLook.textTertiary
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .lookCaps(10.5, weight: .semibold)
                .foregroundStyle(tint)
            Text(hiding.text(text))
                .font(LookFont.text(14, weight: .regular))
                .foregroundStyle(NoopLook.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The pill buttons of the drawings. `isProminent` is the teal one.
struct PFWeekButton529: View {
    let title: String
    var isProminent = false
    var isDisabled = false
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isProminent ? Color(hex: "#06231A") : NoopLook.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(Capsule(style: .continuous).fill(isProminent ? PFWeekColor529.teal : Color.clear))
                .overlay(Capsule(style: .continuous).stroke(isProminent ? PFWeekColor529.teal : NoopLook.divider, lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
    }
}

/// A wrapping row of pills.
struct PFWeekPills529: View {
    let pills: [(text: String, color: Color)]

    var body: some View {
        LookFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(pills.enumerated()), id: \.offset) { _, pill in
                PFChip(text: pill.text, color: pill.color)
            }
        }
    }
}

/// The states every Week screen shares: loading, nothing served, could not be asked.
struct PFWeekState529: View {
    enum Kind { case loading, empty, failed }

    let kind: Kind
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch kind {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text(message).font(LookFont.text(14, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
                }
            case .empty:
                Text(message).font(LookFont.text(14, weight: .regular)).foregroundStyle(NoopLook.textSecondary)
            case .failed:
                Text(message).font(LookFont.text(14, weight: .regular)).foregroundStyle(PFWeekColor529.amber)
                if let retry {
                    PFWeekButton529(title: "Try again", identifier: "plan529-week-retry", action: retry)
                }
            }
        }
        .pfWeekCard()
        .containerIdentifier("plan529-week-state-\(kind)")
    }
}

// MARK: Proposals

/// What the server said to one answer.
enum PFAnswerResult529: Equatable {
    case saved
    /// 404: the change was answered or replaced meanwhile ("That proposal is already handled."). Not an error in "Accept all".
    case handled(String)
    case refused(String)
}

/// Accepts or keeps one change with `POST /app/answer` `{kind: proposal, id, decision: accept | dismiss, key}` (server-jobs-529.md section 8),
/// the same door and code as a Needs you card. The key is `accept-<id>` / `dismiss-<id>` so a retry is safe. A requested swap's id
/// (`swap-...`) works like any other. The reason comes back in the server's own words.
enum PFProposalAnswer529 {
    /// `refreshes` false leaves the full reload of the PaceForge model to the caller (Accept all reloads once at the end).
    @MainActor static func send(id: String, accept: Bool, refreshes: Bool = true) async -> PFAnswerResult529 {
        let model = PFUnified.model
        let answer = PFNeedsAnswer.proposal(id: id, accept: accept)
        if let item = PFEasyModeJobs.item(forProposal: id, in: model.snapshot?.needsYou ?? []) {
            let saved = await model.submitAnswer(answer, for: item, key: key(id: id, accept: accept), refreshes: refreshes)
            if saved { return .saved }
            // Nothing was sent when the card is already being answered or is gone; a refusal leaves its sentence.
            guard let note = model.needsNotes[item.id] else { return .handled("That proposal is already being handled.") }
            let lower = note.lowercased()
            let isHandled = lower.contains("already handled") || lower.contains("no longer waiting") || lower.contains("nothing to add")
            return isHandled ? .handled(note) : .refused(note)
        }
        var body = answer.body
        body["key"] = key(id: id, accept: accept)
        let reply: (status: Int, data: Data)
        do {
            reply = try await PFAPI.postAnswer(body)
        } catch {
            return .refused(PFAnswerOutcome.unreachable.message)
        }
        let outcome = PFAnswerOutcome.from(status: reply.status, data: reply.data)
        if outcome.isSaved {
            if refreshes { await model.refresh() }
            return .saved
        }
        return reply.status == 404 ? .handled(outcome.message) : .refused(outcome.message)
    }

    /// 1 to 64 letters, digits, `-` and `_`.
    static func key(id: String, accept: Bool) -> String {
        let safe = String(id.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" })
        return String(((accept ? "accept-" : "dismiss-") + safe).prefix(64))
    }
}

/// The answers of one Week page: which proposals are being sent and the last refusal.
@MainActor
final class PFWeekDecisions529: ObservableObject {
    @Published private(set) var busy: Set<String> = []
    @Published private(set) var failure: String?
    @Published private(set) var isAnsweringAll = false

    var isBusy: Bool { !busy.isEmpty || isAnsweringAll }

    /// Answers one change; true when the server took it. A change already handled says so and the plan is read again.
    @discardableResult
    func decide(_ id: String, accept: Bool) async -> Bool {
        guard !busy.contains(id) else { return false }
        busy.insert(id)
        failure = nil
        let result = await PFProposalAnswer529.send(id: id, accept: accept)
        busy.remove(id)
        switch result {
        case .saved:
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
            return true
        case .handled(let message):
            failure = message
            NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
            return false
        case .refused(let message):
            failure = message
            return false
        }
    }

    /// "Accept all" has no server call: one accept per change in order, one request at a time. A change already handled (replaced
    /// meanwhile) is skipped; the first refusal stops the loop and shows its sentence. The week is read again once at the end.
    func acceptAll(_ ids: [String]) async {
        isAnsweringAll = true
        failure = nil
        for id in ids {
            busy.insert(id)
            let result = await PFProposalAnswer529.send(id: id, accept: true, refreshes: false)
            busy.remove(id)
            if case .refused(let message) = result {
                failure = message
                break
            }
        }
        await PFUnified.model.refresh()
        isAnsweringAll = false
        NotificationCenter.default.post(name: .pfPlan529Changed, object: nil)
    }
}

extension PFJobInputs {
    /// `session-state` with `optional`: the session stays on the plan but no longer counts as firm.
    static func sessionOptional(sessionID id: String?) -> [String: Any]? {
        guard let id = sessionID(id) else { return nil }
        return ["session_id": id, "state": "optional"]
    }

    /// `session-swap` (Change workout by type): `{date, session_id (absent = add), kind, minutes (optional), again (optional change id)}`.
    static func sessionSwap(date: String, sessionID id: String?, kind: String, minutes: Int?, again: String?) -> [String: Any]? {
        guard isDay(date), ["hyrox", "strength", "run", "bike"].contains(kind) else { return nil }
        var out: [String: Any] = ["date": date, "kind": kind]
        if let id { guard let valid = sessionID(id) else { return nil }; out["session_id"] = valid }
        if let minutes { out["minutes"] = minutes }
        if let again, !again.isEmpty { out["again"] = again }
        return out
    }
}
