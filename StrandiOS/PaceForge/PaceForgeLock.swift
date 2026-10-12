import LocalAuthentication
import SwiftUI
import StrandDesign
import WhoopStore

/// Optional Face ID (or passcode) lock for the PaceForge tab. Off by default; the toggle is in
/// More > PaceForge sync. It covers the tab only: the widgets and notifications show what they always did.
@MainActor
final class PFLock: ObservableObject {
    static let shared = PFLock()

    @Published private(set) var isUnlocked = false
    @Published private(set) var lastAttemptFailed = false
    private var isAuthenticating = false

    func lock() { isUnlocked = false }

    func unlock() async {
        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        var error: NSError?
        // A phone with no passcode has nothing to authenticate with. Staying locked would trap the user
        // behind a lock they cannot open, so it opens.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isUnlocked = true
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                      localizedReason: "Unlock PaceForge")
            isUnlocked = ok
            lastAttemptFailed = !ok
        } catch {
            lastAttemptFailed = true
        }
    }
}

/// What the PaceForge tab shows while it is locked.
struct PFLockedView: View {
    @ObservedObject var lock: PFLock

    var body: some View {
        ScreenScaffold(title: "PaceForge") {
            PFCard("Locked", icon: "lock.fill") {
                VStack(alignment: .leading, spacing: 12) {
                    PFParagraph("PaceForge is locked. Unlock with Face ID or your passcode to see your plan and body data.")
                    Button {
                        Task { await lock.unlock() }
                    } label: {
                        Text("Unlock")
                            .font(StrandFont.subhead.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(StrandPalette.accent)
                    .accessibilityIdentifier("pf-unlock")
                }
            }
        }
        .task { await lock.unlock() }
    }
}

/// Heart-rate recovery for the newest recent workout that has one, written into the widget summary so
/// Siri can answer "what is my heart recovery" without opening the app.
@MainActor
enum PFHeartRecovery {
    static func updateSummary(repo: Repository, hrMax: Int) async {
        guard hrMax > 0, var summary = PFSummary.load() else { return }
        let rows = await repo.workoutRows(days: 14).sorted { $0.endTs > $1.endTs }.prefix(6)
        var found: PFSummary.HeartRecovery?
        for row in rows {
            let outcome = await repo.workoutHeartRateRecoveryOutcome(
                from: row.startTs, to: row.endTs, maxHR: Double(hrMax), source: row.source)
            if case .measured(let result) = outcome {
                found = PFSummary.HeartRecovery(
                    sport: WorkoutSource.displaySport(row.sport),
                    date: PFSummary.dayString(Date(timeIntervalSince1970: TimeInterval(row.endTs))),
                    after1Minute: result.after1Minute, after2Minutes: result.after2Minutes)
                break
            }
        }
        guard summary.heartRecovery != found else { return }
        summary.heartRecovery = found
        summary.save()
    }
}
