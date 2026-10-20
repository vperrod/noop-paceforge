#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Coach: one screen with the New navigation (beta)
//
// The button at the end of the tab bar opens this screen as a sheet, as it always opened NOOP's Coach. Two chips, one mounted at a
// time: Coach (PaceForge's daily brief, Coach's Take, Week review and Needs you) and NOOP chat (the existing NOOP Coach, unchanged).
// A question the launcher or a "Ask the coach" button already collected (AICoachEngine.pendingPrompt) opens the chat chip, which is
// the screen that answers it. With Settings > Coach off there is no NOOP chat chip, and the AI stays off.

enum CoachChip: String, CaseIterable, Identifiable {
    case coach, chat

    /// The chip on show. Reset to Coach at every launch.
    static let storageKey = "noop.coach.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coach: return "Coach"
        case .chat: return "NOOP chat"
        }
    }
}

struct CoachUnifiedView: View {
    @EnvironmentObject private var coach: AICoachEngine
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage(CoachChip.storageKey) private var chipRaw = CoachChip.coach.rawValue

    private var options: [CoachChip] { coachEnabled ? CoachChip.allCases : [.coach] }

    private var chip: CoachChip {
        let wanted = CoachChip(rawValue: chipRaw) ?? .coach
        return options.contains(wanted) ? wanted : .coach
    }

    private var selection: Binding<CoachChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip coach.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Coach", subtitle: "Your brief and your week from PaceForge, and NOOP's coach.",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            CoachUnifiedColumn(options: options, selection: selection)
        }
        // A question already collected for the chat (the launcher, an Ask the coach button, the brief notification) goes to the chat chip.
        .task(id: coach.pendingPrompt) {
            guard coachEnabled, let prompt = coach.pendingPrompt, !prompt.isEmpty else { return }
            chipRaw = CoachChip.chat.rawValue
        }
    }
}

private struct CoachUnifiedColumn: View {
    let options: [CoachChip]
    @Binding var selection: CoachChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if options.count > 1 {
                SectionChips(options: options, selection: $selection, idPrefix: "coach-chip",
                             id: { $0.rawValue }, title: { $0.title })
            }
            CoachChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("coach-host")
    }
}

private struct CoachChipBody: View {
    let chip: CoachChip

    var body: some View {
        UnifiedChipMount(host: "coach", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .coach: return AnyView(CoachPaceForgeChip())
        case .chat: return AnyView(CoachChatChip())
        }
    }
}

/// PaceForge's Coach screen, with what PaceForge is waiting on him for at the top.
private struct CoachPaceForgeChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(CoachPaceForgeContent(snapshot: snapshot)) })
            .containerIdentifier("coach-chip-content-coach")
    }
}

private struct CoachPaceForgeContent: View {
    let snapshot: PFSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !snapshot.needsYou.isEmpty { PFNeedsYouCard(items: snapshot.needsYou) }
            PFCoachView(snapshot: snapshot)
        }
    }
}

/// NOOP's own Coach, as it was.
private struct CoachChatChip: View {
    var body: some View {
        CoachView()
            .containerIdentifier("coach-chip-content-chat")
    }
}
#endif
