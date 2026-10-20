import Foundation
import SwiftUI
import StrandDesign

// The opt-in "New PaceForge refresh (beta)". Off by default: with the switch off nothing in this file runs and every PaceForge
// screen takes the refresh path build 477 had. The switch is read once, at launch (`PFBeta.captureAtLaunch()`), so a change
// applies after the app is restarted.

enum PFBeta {
    static let defaultsKey = "pfRefreshBeta"

    /// Read once per launch; the Settings switch only writes the preference.
    static let isOn: Bool = UserDefaults.standard.bool(forKey: defaultsKey)

    /// Called from the app's init so the value is the one the app started with, however late a screen first asks.
    static func captureAtLaunch() {
        if isOn { NoopDiag.crumb("refresh.beta enabled") }
    }

    /// The beta could not finish: the caller runs the build 477 path instead. The reason is a short code, never a payload.
    static func fallback(_ reason: String) {
        NoopDiag.crumb("refresh.beta.fallback \(reason)")
    }

    static func reason(_ error: Error) -> String {
        if let urlError = error as? URLError { return "url\(urlError.code.rawValue)" }
        if error is CancellationError { return "cancelled" }
        if error is CocoaError { return "cocoa\((error as? CocoaError)?.code.rawValue ?? 0)" }
        return String(describing: type(of: error))
    }
}

/// Runs a synchronous build on its own thread with a large stack. The builder is a very large function; on a Swift-concurrency
/// thread (about 512 KB of stack) it overflowed in build 478.
enum PFBuildThread {
    static let stackBytes = 16 * 1024 * 1024

    static func run<T>(_ label: String, _ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            let thread = Thread {
                NoopDiag.crumb("refresh.beta.thread \(label)", ["stack_kb": Double(Thread.current.stackSize / 1024)])
                continuation.resume(returning: work())
            }
            thread.stackSize = stackBytes
            thread.qualityOfService = .userInitiated
            thread.name = "pf-build"
            thread.start()
        }
    }
}

extension PFAPI {
    /// `data/manifest.json`: the hash of every document, by path. nil when the server does not serve it (an older server, offline,
    /// a login page) or lists nothing: the caller then downloads every document. Not saved on the phone, and never asked in a
    /// UI-test fixture.
    static func fetchManifest() async -> [String: String]? {
        guard !isFixture, let data = try? await SelfHostedPushClient.paceForgeGet("data/manifest.json") else { return nil }
        var hashes: [String: String] = [:]
        for (path, entry) in PFJ(data: data)["docs"].dict {
            if let sha = entry["sha1"].string { hashes[path] = sha.lowercased() }
        }
        return hashes.isEmpty ? nil : hashes
    }
}

#if os(iOS)
/// Settings > Tools > New PaceForge refresh (beta).
struct PFRefreshBetaToggle: View {
    @AppStorage(PFBeta.defaultsKey) private var isEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isEnabled) {
                Text("New PaceForge refresh (beta)")
                    .font(StrandFont.body)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .toggleStyle(.switch)
            .tint(StrandPalette.accent)
            .frame(minHeight: 44)
            .accessibilityIdentifier("settings-tool-pfrefreshbeta")
            Text("Downloads only the PaceForge documents that changed. Off keeps the refresh you have today. Restart NOOP to apply a change.")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
