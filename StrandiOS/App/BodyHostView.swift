#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Body: a More screen with the unified navigation
//
// PaceForge's Body screen (the Hume scale: trend, score, composition, goals, readings) and the Lab Book as two chips, one mounted at a
// time. Both are the screens that exist today, unchanged.

enum BodyChip: String, CaseIterable, Identifiable {
    case body, labBook

    /// The chip on show. Reset to Body at every launch.
    static let storageKey = "noop.body.chip"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .body: return "Body"
        case .labBook: return "Lab Book"
        }
    }
}

struct BodyHostView: View {
    @AppStorage(BodyChip.storageKey) private var chipRaw = BodyChip.body.rawValue

    private var chip: BodyChip { BodyChip(rawValue: chipRaw) ?? .body }

    private var selection: Binding<BodyChip> {
        Binding(
            get: { chip },
            set: { new in
                guard new != chip else { return }
                NoopDiag.crumb("nav.chip body.\(new.rawValue)")
                chipRaw = new.rawValue
            }
        )
    }

    var body: some View {
        ScreenScaffold(title: "Body", subtitle: "Your scale readings and your lab results.",
                       onRefresh: { await PFUnified.model.refresh() }, lazy: true, topBackground: liquidScaffoldSky()) {
            BodyColumn(selection: selection)
        }
    }
}

private struct BodyColumn: View {
    @Binding var selection: BodyChip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionChips(options: BodyChip.allCases, selection: $selection, idPrefix: "body-chip",
                         id: { $0.rawValue }, title: { $0.title })
            BodyChipBody(chip: selection)
                .id(selection)
                .environment(\.screenScaffoldEmbedded, true)
        }
        .containerIdentifier("body-host")
    }
}

private struct BodyChipBody: View {
    let chip: BodyChip

    var body: some View {
        UnifiedChipMount(host: "body", name: chip.rawValue, content: content)
    }

    private var content: AnyView {
        switch chip {
        case .body: return AnyView(BodyPaceForgeChip())
        case .labBook: return AnyView(LabBookView().containerIdentifier("body-chip-content-labBook"))
        }
    }
}

private struct BodyPaceForgeChip: View {
    var body: some View {
        PFSnapshotHost(content: { snapshot in AnyView(BodyPaceForgeContent(snapshot: snapshot)) })
            .containerIdentifier("body-chip-content-body")
    }
}

/// The Body screen, or its placeholder while Settings > Hide numbers hides body weight and body fat.
private struct BodyPaceForgeContent: View {
    let snapshot: PFSnapshot
    private let hiding = PFHiding()

    var body: some View {
        if hiding.hides(.body) {
            PFBodyHiddenView()
        } else {
            VStack(alignment: .leading, spacing: 16) {
                PFPageNote(key: "body")
                PFBodyView(snapshot: snapshot)
            }
        }
    }
}
#endif
