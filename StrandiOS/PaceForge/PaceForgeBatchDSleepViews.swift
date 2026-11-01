#if os(iOS)
import SwiftUI
import StrandDesign

// "PaceForge sleep" on the Sleep tab, under the planner (see PaceForgeBandBatchD.swift for the numbers): the four sleep tiles for the
// latest night against their own usual band, Garmin's stage shares with their caveat, and when the strap's heart rate settled. Each part
// names its source (PaceForge's Garmin night, Garmin, the WHOOP strap read by NOOP) and none is merged with NOOP's own sleep numbers.
// Overnight, so a watch worn by day only leaves the whole section out.

// MARK: - The store the batch D cards share

@MainActor
final class PFBatchDStore: ObservableObject {
    static let shared = PFBatchDStore()

    @Published private(set) var settle: PFSleepSettle?
    @Published private(set) var tiles: PFSleepTiles?
    @Published private(set) var shares: PFStageShares?
    @Published private(set) var stressLoad: PFStressLoad?
    @Published private(set) var activeHours: PFActiveHours?
    private var lastFetch: Date?

    private init() {}

    func refreshIfStale() async {
        if let lastFetch, Date().timeIntervalSince(lastFetch) < 300 { return }
        guard PFAPI.isConfigured else { return }
        async let settleData = Self.read(PFBatchDParse.settlePath)
        async let tilesData = Self.read(PFBatchDParse.tilesPath)
        async let sharesData = Self.read(PFBatchDParse.sharesPath)
        async let stressData = Self.read(PFBatchDParse.stressLoadPath)
        async let activeData = Self.read(PFBatchDParse.activeHoursPath)
        let (a, b, c, d, e) = await (settleData, tilesData, sharesData, stressData, activeData)
        let newSettle = PFBatchDParse.sleepSettle(PFJ(data: a))
        let newTiles = PFBatchDParse.sleepTiles(PFJ(data: b))
        let newShares = PFBatchDParse.stageShares(PFJ(data: c))
        let newStress = PFBatchDParse.stressLoad(PFJ(data: d))
        let newActive = PFBatchDParse.activeHours(PFJ(data: e))
        // An equal assignment would still redraw every card that watches the store.
        if settle != newSettle { settle = newSettle }
        if tiles != newTiles { tiles = newTiles }
        if shares != newShares { shares = newShares }
        if stressLoad != newStress { stressLoad = newStress }
        if activeHours != newActive { activeHours = newActive }
        lastFetch = Date()
    }

    /// The server's copy, else (offline) the one the last good fetch left on the phone. A fixture never reads the cache.
    nonisolated private static func read(_ path: String) async -> Data? {
        let data = await PFAPI.fetchOptional(path)
        if data == nil, PFAPI.usesPhoneState { return PFStore.read(path: path) }
        return data
    }
}

// MARK: - Small shared label

/// A small caps title with whose numbers follow, right-aligned.
struct PFSourceLabel: View {
    let title: String
    let source: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
            Spacer(minLength: 8)
            if let source {
                Text(source)
                    .font(LookFont.text(11, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

private func pfStandingColor(_ standing: String) -> Color {
    switch standing {
    case "better": return PFColor.positive
    case "worse": return PFColor.warning
    default: return PFColor.sky
    }
}

// MARK: - The section

/// Under the planner and the regularity tile. Started from here so the load runs whether or not there is anything to draw yet.
struct PFSleepSection: View {
    @ObservedObject private var store = PFBatchDStore.shared
    @ObservedObject private var reports = PFReportsStore.shared

    private var hasContent: Bool { store.tiles != nil || store.shares != nil || store.settle != nil }

    var body: some View {
        VStack(spacing: 0) {
            if reports.showsOvernight && hasContent {
                PFSleepSectionCard(tiles: store.tiles, shares: store.shares, settle: store.settle)
                    .padding(.top, NoopMetrics.sectionSpacing)
            }
        }
        .task { await store.refreshIfStale() }
    }
}

struct PFSleepSectionCard: View {
    let tiles: PFSleepTiles?
    let shares: PFStageShares?
    let settle: PFSleepSettle?

    var body: some View {
        PFCard("PaceForge sleep", icon: "bed.double.fill") {
            VStack(alignment: .leading, spacing: 18) {
                if let tiles { PFSleepTilesBlock(tiles: tiles) }
                if let shares { PFStageSharesBlock(shares: shares) }
                if let settle { PFSettleBlock(settle: settle) }
            }
        }
        .containerIdentifier("pf-sleep-section")
    }
}

private struct PFSleepTilesBlock: View {
    let tiles: PFSleepTiles

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PFSourceLabel(title: "Night of \(PFFormat.shortDate(tiles.date))", source: tiles.source)
            ForEach(tiles.tiles) { tile in PFSleepTileRow(tile: tile) }
        }
    }
}

private struct PFSleepTileRow: View {
    let tile: PFSleepTile
    private let hiding = PFHiding()

    private var bar: PFBandLogic.Bar? {
        guard let value = tile.value, tile.bandLow != nil || tile.bandHigh != nil else { return nil }
        return PFBandLogic.bar(value: value, low: tile.bandLow, high: tile.bandHigh)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(PFBatchDLogic.tileTitle(tile.key)).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                if let word = PFBatchDLogic.standingWord(tile.standing) { PFChip(text: word, color: pfStandingColor(tile.standing)) }
            }
            if let text = tile.text {
                Text(hiding.text(text))
                    .font(LookFont.text(15, weight: .semibold))
                    .foregroundStyle(NoopLook.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let bar { PFRangeTrack(bar: bar, color: pfStandingColor(tile.standing)) }
            if let gloss = tile.gloss {
                Text(hiding.text(gloss))
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-sleep-tile-\(tile.key)")
    }
}

private struct PFStageSharesBlock: View {
    let shares: PFStageShares

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PFSourceLabel(title: "Stage shares", source: shares.source)
            ForEach(shares.shares) { share in PFStageShareRow(share: share) }
            if let line = shares.line { PFParagraph(line) }
            if let caveat = shares.caveat {
                Text(caveat)
                    .font(LookFont.text(12.5, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let gloss = shares.gloss {
                Text(gloss)
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PFStageShareRow: View {
    let share: PFStageShare

    private var bar: PFBandLogic.Bar? { PFBandLogic.bar(value: share.pct, low: share.usualPct, high: share.usualPct) }

    private var usualText: String? { share.usualPct.map { "usual \(Safe.int($0))%" } }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(PFBatchDLogic.stageTitle(share.key)).lookCaps(11).foregroundStyle(NoopLook.textSecondary)
                Spacer(minLength: 8)
                Text(String(Safe.int(share.pct)) + "%").font(LookFont.numeral(20)).foregroundStyle(NoopLook.textPrimary)
                if let usualText {
                    Text(usualText).font(LookFont.text(12, weight: .medium)).foregroundStyle(NoopLook.textTertiary)
                }
                if let word = PFBatchDLogic.stageWord(share) { PFChip(text: word, color: PFColor.warning) }
            }
            if let bar { PFRangeTrack(bar: bar) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-stage-share-\(share.key)")
    }
}

private struct PFSettleBlock: View {
    let settle: PFSleepSettle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PFSourceLabel(title: "Heart-rate settle time", source: settle.source)
            if let sentence = settle.sentence { PFParagraph(sentence) }
            if let gloss = settle.status?.gloss {
                Text(gloss)
                    .font(LookFont.text(12, weight: .medium))
                    .foregroundStyle(NoopLook.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pf-sleep-settle")
    }
}
#endif
