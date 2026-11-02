import SwiftUI
import StrandDesign

// The short paragraph at the top of a screen: PaceForge's one assessment of all the metrics that screen is about, written on the
// server (data/page-notes.json) and only shown here. Best effort: with no file, an empty text or a file older than two days a
// screen shows nothing at all and looks as it did before.

/// Keeps the page notes of the last good fetch. Every screen's note reads this one store; each asks it to refresh itself when its
/// copy is more than five minutes old. Read-only: nothing here writes to the server.
@MainActor
final class PFPageNotesStore: ObservableObject {
    static let shared = PFPageNotesStore()

    /// nil until a file has loaded; a screen shows nothing before that.
    @Published private(set) var notes: PFPageNotes?

    private var lastFetch: Date?
    private var inFlight: Task<Void, Never>?

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
        await refresh()
    }

    /// Overlapping callers share the load already running.
    func refresh() async {
        if let inFlight {
            await inFlight.value
            return
        }
        let task = Task { [self] in
            await load()
            inFlight = nil
        }
        inFlight = task
        await task.value
    }

    private func load() async {
        guard PFAPI.isConfigured else { return }
        // The copy on the phone first, so the note is there while the network answers.
        if notes == nil, PFAPI.usesPhoneState { publish(PFStore.read(path: PFDocs.pageNotes)) }
        if let fresh = await PFAPI.fetchOptional(PFDocs.pageNotes) { publish(fresh) }
        lastFetch = Date()
    }

    private func publish(_ data: Data?) {
        let parsed = PFWave2Parse.pageNotes(PFJ(data: data))
        // Screens observe this store; an equal assignment would still redraw them.
        if parsed != notes { notes = parsed }
    }
}

/// The note for one screen. `key` is the server's page name: today, coach, training, sleep, recovery, effort, vitals, stress,
/// insights or body. Draws nothing when there is no note to show.
///
/// It reads as one line (the tone word and the first sentence) until it is tapped, then opens in place to the whole paragraph with
/// the "Not today" menu. `alwaysOpen` is for the Coach, where the whole assessment is the point.
struct PFPageNote: View {
    let key: String
    var alwaysOpen = false

    @ObservedObject private var store = PFPageNotesStore.shared
    @ObservedObject private var dismissals = PFDismissStore.shared
    @State private var isOpen = false
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Not today" on the note: key `pagenote:<page>`, hidden until its text changes or for the day. Only the phone's list is
            // read here; the Hidden cards row on Today brings it back.
            if let notes = store.notes, let note = notes.note(key, today: PFAPI.todayISO),
               !PFDismissLogic.isHidden(key: PFDismissKey.pageNoteKey(key), text: PFDismissKey.pageNoteText(note),
                                        today: PFAPI.todayISO, local: dismissals.local, server: []) {
                if alwaysOpen || isOpen {
                    card(note, updated: notes.updatedLabel(today: PFAPI.todayISO))
                } else {
                    collapsedRow(note)
                }
            }
        }
        // An empty view never runs its own .task, so the load hangs on a view that is always there.
        .background(Color.clear.frame(width: 0, height: 0).task { await store.refreshIfStale() })
    }

    /// The tone word and the first sentence on one line, a chevron on the right. The whole row opens the note.
    private func collapsedRow(_ note: PFPageNoteItem) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { isOpen = true }
        } label: {
            HStack(spacing: 8) {
                paragraph(note, text: Self.firstSentence(note.text))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityLabel(Text(verbatim: hiding.text(note.text)))
        .accessibilityHint(Text("Shows the whole note"))
        .accessibilityIdentifier("pf-page-note-\(key)")
    }

    private func card(_ note: PFPageNoteItem, updated: String?) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                paragraph(note, text: note.text)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let updated {
                    Text("Updated \(updated)")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !alwaysOpen else { return }
                withAnimation(.easeOut(duration: 0.2)) { isOpen = false }
            }
            .accessibilityElement(children: .combine)
            .accessibilityActions {
                if !alwaysOpen {
                    Button("Collapse") { withAnimation(.easeOut(duration: 0.2)) { isOpen = false } }
                }
            }
            .accessibilityIdentifier("pf-page-note-\(key)")
            PFDismissMenu(key: PFDismissKey.pageNoteKey(key), title: "the note on this screen", text: PFDismissKey.pageNoteText(note),
                          todayISO: PFAPI.todayISO)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }

    /// The tone word first (nothing for ok), then `text` with Hide numbers applied.
    private func paragraph(_ note: PFPageNoteItem, text: String) -> Text {
        let sentence = Text(verbatim: hiding.text(text))
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
        guard let lead = toneWord(note.tone) else { return sentence }
        return lead + Text(verbatim: " ") + sentence
    }

    private func toneWord(_ tone: String) -> Text? {
        switch tone {
        case "alert":
            return Text("Alert").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(PFColor.critical)
        case "careful":
            return Text("Careful").font(StrandFont.subhead.weight(.semibold)).foregroundStyle(PFColor.warning)
        default:
            return nil
        }
    }

    /// Everything up to the first full stop, question or exclamation mark that is followed by a space; the whole text when there is none.
    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var previous: Character?
        for index in trimmed.indices {
            let character = trimmed[index]
            if character == " ", let previous, ".!?".contains(previous) { return String(trimmed[..<index]) }
            previous = character
        }
        return trimmed
    }
}

extension PFSegment {
    /// The server's page name for the note on this segment of the PaceForge tab (unified navigation off).
    var pageNoteKey: String {
        switch self {
        case .today: return "today"
        case .coach: return "coach"
        case .week: return "training"
        case .insights: return "insights"
        case .body: return "body"
        }
    }
}
