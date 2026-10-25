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
struct PFPageNote: View {
    let key: String

    @ObservedObject private var store = PFPageNotesStore.shared
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notes = store.notes, let note = notes.note(key, today: PFAPI.todayISO) {
                card(note, updated: notes.updatedLabel(today: PFAPI.todayISO))
            }
        }
        // An empty view never runs its own .task, so the load hangs on a view that is always there.
        .background(Color.clear.frame(width: 0, height: 0).task { await store.refreshIfStale() })
    }

    private func card(_ note: PFPageNoteItem, updated: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            paragraph(note)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let updated {
                Text("Updated \(updated)")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-page-note-\(key)")
    }

    /// The tone word first (nothing for ok), then the server's text with Hide numbers applied.
    private func paragraph(_ note: PFPageNoteItem) -> Text {
        let text = Text(verbatim: hiding.text(note.text))
            .font(StrandFont.subhead)
            .foregroundStyle(StrandPalette.textSecondary)
        guard let lead = toneWord(note.tone) else { return text }
        return lead + Text(verbatim: " ") + text
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
