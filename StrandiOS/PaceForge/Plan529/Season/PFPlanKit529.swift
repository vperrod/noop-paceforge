import SwiftUI
import StrandDesign

// The small shared pieces of the Season, Calendar, Reports and plan-settings screens (build 529): the card, the row, the pill, the
// phase colours and bar, the hours text and the "loading, empty, failed" placeholder. Nothing here is generic over its content (a
// generic container carried every screen's whole view tree in its type name, which froze the PaceForge tab in build 472).

// MARK: Card, overline, row, pill

extension View {
    /// The look's card: a 12 pt tile on the dark gradient.
    func planCard529(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: NoopLook.Metric.tileRadius, style: .continuous).fill(NoopLook.card))
    }
}

/// The small caps label over a card's content.
struct PFOver529: View {
    let text: String

    var body: some View {
        Text(text)
            .lookCaps(10.5, weight: .semibold)
            .foregroundStyle(NoopLook.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct PFPill529: View {
    enum Tone { case teal, amber, grey, red, blue }

    let text: String
    var tone: Tone = .teal

    private var color: Color {
        switch tone {
        case .teal: return NoopLook.trendUp
        case .amber: return NoopLook.trendDown
        case .grey: return NoopLook.textTertiary
        case .red: return NoopLook.alert
        case .blue: return Color(hex: NoopLook.Hex.coachBlue)
        }
    }

    var body: some View {
        Text(text)
            .lookCaps(10, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .lineLimit(1)
    }
}

/// One row of a card: an optional leading label (a date), a title with a line under it, and a trailing text or chevron.
struct PFRow529: View {
    var lead: String? = nil
    var leadWidth: CGFloat = 50
    var dot: Color? = nil
    var isNew = false
    let title: String
    var sub: String? = nil
    var trailing: String? = nil
    var trailingPill: PFPill529? = nil
    var showsChevron = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let lead {
                Text(lead)
                    .lookCaps(12, weight: .semibold)
                    .foregroundStyle(NoopLook.textTertiary)
                    .frame(width: leadWidth, alignment: .leading)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if isNew {
                        Circle().fill(NoopLook.trendUp).frame(width: 7, height: 7)
                            .accessibilityHidden(true)
                    }
                    if let dot {
                        Circle().fill(dot).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sub, !sub.isEmpty {
                    Text(sub)
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailingPill { trailingPill }
            if let trailing {
                Text(trailing)
                    .font(LookFont.text(12.5))
                    .foregroundStyle(NoopLook.textTertiary)
                    .lineLimit(1)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 9)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A hairline between the rows of a card.
struct PFDivider529: View {
    var body: some View {
        Rectangle().fill(NoopLook.divider).frame(height: 1)
    }
}

/// A pill-shaped button in the drawings' two weights: the filled one is the main action.
struct PFPillButton529: View {
    let title: String
    var isMain = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lookCaps(11, weight: .semibold)
                .foregroundStyle(isMain ? Color.black.opacity(0.85) : NoopLook.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(isMain ? StrandPalette.accent : Color.clear))
                .overlay(Capsule().strokeBorder(isMain ? Color.clear : NoopLook.divider, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: Phases

/// The season plan's one phase vocabulary (recover, build, sharpen, taper, race) and its colours.
enum PFPhase529 {
    struct Entry: Identifiable {
        let key: String
        let label: String
        var id: String { key }
    }

    static let legend: [Entry] = [
        Entry(key: "recover", label: "recover"), Entry(key: "build", label: "build"), Entry(key: "sharpen", label: "sharpen"),
        Entry(key: "taper", label: "taper"), Entry(key: "race", label: "race"),
    ]

    static func color(_ key: String?) -> Color {
        switch key ?? "" {
        case "recover", "recovery": return PFColor.positive.opacity(0.55)
        case "build": return PFColor.sky
        case "sharpen": return PFColor.violet
        case "taper": return PFColor.warning
        case "race": return PFColor.critical
        default: return NoopLook.textTertiary
        }
    }
}

/// How an effort word is drawn in the calendar and the week strip.
enum PFEffort529 {
    static func color(_ effort: String?) -> Color {
        switch effort ?? "" {
        case "easy": return PFColor.positive
        case "moderate": return PFColor.sky
        case "hard": return PFColor.warning
        case "race": return PFColor.critical
        default: return NoopLook.textTertiary
        }
    }
}

private struct PFWeightKey529: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

/// Lays its children side by side with widths in proportion to their weights, so a phase bar needs no GeometryReader.
struct PFProportionalRow529: Layout {
    var spacing: CGFloat = 1

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 200, height: proposal.height ?? 12)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let total = max(1, subviews.reduce(CGFloat(0)) { $0 + $1[PFWeightKey529.self] })
        let free = max(0, bounds.width - spacing * CGFloat(subviews.count - 1))
        var x = bounds.minX
        for subview in subviews {
            let width = max(2, free * subview[PFWeightKey529.self] / total)
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }
}

/// A bar of phases, each segment as wide as its days.
struct PFPhaseBar529: View {
    let segments: [PFSeasonDoc.BarSegment]
    var height: CGFloat = 12

    var body: some View {
        PFProportionalRow529 {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Rectangle()
                    .fill(PFPhase529.color(segment.phase))
                    .layoutValue(key: PFWeightKey529.self, value: CGFloat(max(segment.days ?? 1, 1)))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct PFPhaseLegend529: View {
    var body: some View {
        LookFlowLayout(spacing: 12, lineSpacing: 4) {
            ForEach(PFPhase529.legend) { entry in
                HStack(spacing: 5) {
                    Circle().fill(PFPhase529.color(entry.key)).frame(width: 8, height: 8)
                    Text(entry.label)
                        .font(LookFont.text(11.5))
                        .foregroundStyle(NoopLook.textTertiary)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The optional `story` and `insights` of a daily or monthly short block: the story under the verdict, then small titled blocks. Long text
/// wraps and is never clamped.
struct PFStoryBlocks529: View {
    let story: String?
    let insights: [(title: String, text: String)]
    private let hiding = PFHiding()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let story, !story.isEmpty {
                Text(hiding.text(story))
                    .font(LookFont.text(14.5))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("report-story")
            }
            ForEach(Array(insights.enumerated()), id: \.offset) { _, insight in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hiding.text(insight.title))
                        .font(LookFont.text(13.5, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(hiding.text(insight.text))
                        .font(LookFont.text(13))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("report-insight")
            }
        }
    }
}

// MARK: Numbers

enum PFHours529 {
    /// 3.42 -> "3 h 25", 3.0 -> "3 h", 0.5 -> "30 min".
    static func text(_ hours: Double) -> String {
        guard hours.isFinite, hours > 0 else { return "0 h" }
        let minutes = Int((hours * 60).rounded())
        let whole = minutes / 60
        let rest = minutes % 60
        if whole == 0 { return "\(rest) min" }
        return rest == 0 ? "\(whole) h" : "\(whole) h \(String(format: "%02d", rest))"
    }
}

/// An ISO week key for any day: "2026-W47".
enum PFISOWeek529 {
    static func key(_ iso: String) -> String { PFFormat.isoWeekKey(iso) }

    /// The week before the one that holds `iso`.
    static func previous(_ iso: String) -> String { key(PFFormat.addDays(PFFormat.monday(of: iso), -7)) }
}

// MARK: Placeholder for a document that is not on screen

/// What a screen draws while its document is loading, not served, or could not be fetched (with a Try again).
struct PFDocPlaceholder529: View {
    enum Kind { case loading, empty, failed }

    let kind: Kind
    var emptyTitle = "Nothing here yet"
    var emptyText = ""
    var failedText = "PaceForge could not be reached, and no saved copy is on this phone."
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading")
                        .font(LookFont.text(14.5))
                        .foregroundStyle(NoopLook.textSecondary)
                }
            case .empty:
                Text(emptyTitle)
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                if !emptyText.isEmpty {
                    Text(emptyText)
                        .font(LookFont.text(13.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .failed:
                Text(failedText)
                    .font(LookFont.text(14))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let retry {
                    Button(action: retry) {
                        Text("Try again")
                            .font(LookFont.text(14, weight: .semibold))
                            .foregroundStyle(StrandPalette.accent)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plan529-retry")
                }
            }
        }
        .planCard529()
        .containerIdentifier("plan529-placeholder-\(String(describing: kind))")
    }
}

/// "Showing the copy saved on this phone": a document that could not be fetched but has a saved copy.
struct PFStaleNote529: View {
    var body: some View {
        Text("Showing the copy saved on this phone. PaceForge could not be reached.")
            .font(LookFont.text(12))
            .foregroundStyle(PFColor.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("plan529-stale")
    }
}

// MARK: Reload after the screen's pull to refresh

/// The Plan tab's pull to refresh reloads the PaceForge snapshot; a document this section reads itself reloads when that finishes.
@MainActor struct PFReloadsAfterPull529: ViewModifier {
    @ObservedObject private var model = PFUnified.model
    let reload: () async -> Void

    init(reload: @escaping () async -> Void) { self.reload = reload }

    func body(content: Content) -> some View {
        content.onChange(of: model.isRefreshing) { wasRefreshing, isRefreshing in
            if wasRefreshing && !isRefreshing { Task { await reload() } }
        }
    }
}

extension View {
    func reloadsAfterPull529(_ reload: @escaping () async -> Void) -> some View {
        modifier(PFReloadsAfterPull529(reload: reload))
    }
}

// MARK: The PaceForge lock

/// The documents this section reads itself sit behind the same Face ID lock as the snapshot's screens (`PFSnapshotHost`).
@MainActor struct PFLockGate529: ViewModifier {
    @ObservedObject private var lock = PFLock.shared
    @AppStorage(PFPrefs.lockKey) private var lockEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        Group {
            if lockEnabled && !lock.isUnlocked {
                PFLockedView(lock: lock)
            } else {
                content
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { lock.lock() }
        }
    }
}

extension View {
    func lockGate529() -> some View { modifier(PFLockGate529()) }
}

// MARK: Screens that stand on their own

extension View {
    /// The frame of a destination of this section: the look's background and scroll, the title and an identifier.
    func planScreen529(title: String, identifier: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                self.lockGate529()
            }
            .padding(.horizontal, NoopLook.Metric.screenInset)
            .padding(.top, 8)
            .padding(.bottom, NoopMetrics.tabBarClearance)
        }
        .lookScreenBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .containerIdentifier(identifier)
    }
}
