import SwiftUI
import StrandDesign

/// Where one planned session stands on the way to the watch, from `GET api/watch-status`: on the week's item card and in the session sheet.
/// "On your watch" only when the server read Garmin's own list back; a session Garmin Connect holds is "not yet confirmed on the watch".
/// Nothing is shown for a session the status does not list, and nothing is claimed from a copy the phone could not refresh.
@MainActor
enum PFWatchStatusStore529 {
    static let shared = PFDocStore529<PFWatchStatusDoc>(path: PFDocPath529.watchStatus)
}

struct PFWatchChip529: View {
    let sessionID: String?

    @ObservedObject private var store = PFWatchStatusStore529.shared

    var body: some View {
        content
            .task { await store.refreshIfStale(maxAge: 120) }
    }

    @ViewBuilder private var content: some View {
        if let id = sessionID, let session = store.doc?.session(id), let line = PFWatchStatus529.line(session) {
            if store.isStale {
                row(text: "Watch status could not be refreshed", detail: "Open this again with a connection to see where it stands.",
                    color: NoopLook.textTertiary, id: id)
            } else {
                row(text: line.text, detail: line.detail, color: color(line.tone), id: id)
            }
        }
    }

    private func row(text: String, detail: String?, color: Color, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(text, systemImage: "applewatch")
                .font(LookFont.text(13, weight: .medium))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(LookFont.text(12, weight: .regular))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan529-watch-\(id)")
    }

    private func color(_ tone: PFWatchStatus529.Tone) -> Color {
        switch tone {
        case .onWatch: return PFWeekColor529.teal
        case .pending: return NoopLook.textSecondary
        case .blocked: return NoopLook.textTertiary
        case .failed: return PFWeekColor529.amber
        }
    }
}
