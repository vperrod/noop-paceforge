import SwiftUI
import StrandDesign

// Two small actions that go through the job door (PaceForgeJob.swift): "Sync Garmin now" on the PaceForge sync page, and a thumbs
// up or down under a Coach reply.

/// "Sync Garmin now": asks PaceForge to fetch the newest data from Garmin (`sync`, a slow job that takes a few seconds, or a minute
/// or more behind a Garmin rate limit) and says when it is done. It is not the NOOP database sync the page's "Sync now" runs.
struct PFSyncGarminRow: View {
    @StateObject private var tracker = PFJobTracker()

    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Sync Garmin now") { Task { await sync() } }
                .buttonStyle(.bordered)
                .disabled(isBusy)
                .accessibilityIdentifier("pf-sync-garmin")
            status
            Text("Asks PaceForge to pull your newest data from Garmin.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var status: some View {
        switch tracker.phase {
        case .sending, .working:
            Text("Syncing Garmin")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .done:
            Text("Garmin sync finished.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textSecondary)
        case .failed(let message):
            Text(message)
                .font(StrandFont.caption)
                .foregroundStyle(PFColor.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    @MainActor private func sync() async {
        if case .success = await tracker.run(.sync, inputs: [:]) {
            // The new Garmin data reaches the screens on the next load.
            await PFUnified.model.refresh()
        }
    }
}

/// Thumbs up or down under one Coach reply (`coach-feedback`). One tap sends it; a rating is remembered on the phone so the row
/// reads "Noted" afterwards.
struct PFRateRow: View {
    let kind: String
    let id: String

    @StateObject private var tracker = PFJobTracker()
    @State private var verdict: PFVerdict?

    private var storageKey: String { PFCoachFeedback.key(kind: kind, id: id) }
    private var isBusy: Bool { tracker.phase == .sending || tracker.phase == .working }

    var body: some View {
        HStack(spacing: 4) {
            if let verdict {
                Image(systemName: verdict == .up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(StrandPalette.textTertiary)
                Text("Noted")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            } else {
                Text("Was this useful?")
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
                thumb(.up)
                thumb(.down)
                if case .failed(let message) = tracker.phase {
                    Text(message)
                        .font(StrandFont.caption)
                        .foregroundStyle(PFColor.warning)
                        .lineLimit(2)
                }
            }
        }
        .onAppear { verdict = Self.stored(storageKey) }
    }

    private func thumb(_ value: PFVerdict) -> some View {
        Button {
            Task { await rate(value) }
        } label: {
            Image(systemName: value == .up ? "hand.thumbsup" : "hand.thumbsdown")
                .font(.system(size: 15))
                .foregroundStyle(StrandPalette.textSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(Self.accessibilityText(value))
        .accessibilityIdentifier("pf-rate-\(value.rawValue)")
    }

    private static func accessibilityText(_ value: PFVerdict) -> LocalizedStringKey {
        switch value {
        case .up: return "Good coaching"
        case .down: return "Missed the mark"
        }
    }

    @MainActor private func rate(_ value: PFVerdict) async {
        let inputs = PFJobInputs.coachFeedback(kind: kind, id: id, verdict: value)
        if case .success = await tracker.run(.coachFeedback, inputs: inputs) {
            Self.remember(value, key: storageKey)
            verdict = value
        }
    }

    private static func stored(_ key: String) -> PFVerdict? {
        let saved = UserDefaults.standard.dictionary(forKey: PFCoachFeedback.storageKey) as? [String: String]
        guard let raw = saved?[key] else { return nil }
        return PFVerdict(rawValue: raw)
    }

    private static func remember(_ value: PFVerdict, key: String) {
        var saved = (UserDefaults.standard.dictionary(forKey: PFCoachFeedback.storageKey) as? [String: String]) ?? [:]
        saved[key] = value.rawValue
        UserDefaults.standard.set(saved, forKey: PFCoachFeedback.storageKey)
    }
}
