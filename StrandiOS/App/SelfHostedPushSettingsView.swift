#if os(iOS)
import SwiftUI
import StrandDesign

/// Opt-in configuration for the NOOP ↔ PaceForge sync.
struct SelfHostedPushSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(SelfHostedPushClient.enabledKey) private var enabled = false
    @AppStorage(SelfHostedPushClient.endpointKey) private var endpoint = ""
    @AppStorage(SelfHostedPushClient.lastSuccessKey) private var lastSuccess = 0.0
    @AppStorage(SelfHostedPushClient.replicaConflictCountKey) private var conflictCount = 0
    @State private var token = ""
    @State private var status = "Off. Nothing syncs until you enable this."
    @State private var busy = false

    var body: some View {
        ScreenScaffold(title: "PaceForge sync",
                       subtitle: "Keep NOOP data, Garmin metrics and activities in sync.") {
            StrandCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle(isOn: $enabled) {
                        Text("Enable direct sync")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.textPrimary)
                    }
                    .toggleStyle(.switch)
                    .tint(StrandPalette.accent)
                    .disabled(!enabled && !ready)
                    Text("On first sync, NOOP makes a safe copy of this iPhone database on your private Mini PC. After that, changes sync both ways; PaceForge reads the Mini PC copy. Garmin and Hume values keep their own source labels. Sync runs when NOOP opens or finishes a strap sync, and you can also run it here.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("PaceForge endpoint URL", text: $endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textFieldStyle(.roundedBorder)
                    SecureField("PaceForge bearer token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 10) {
                        Button("Save token") {
                            guard SelfHostedPushClient.saveToken(token) else {
                                status = "Could not save the token to iPhone Keychain."; return
                            }
                            token = ""
                            status = "Token saved securely on this iPhone."
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Test connection") { runTest() }
                            .buttonStyle(.bordered)
                            .disabled(busy)
                    }
                    HStack(spacing: 10) {
                        Button("Sync now") { sendNow() }
                            .buttonStyle(.bordered)
                            .disabled(busy || !enabled)
                        Button("Forget token", role: .destructive) {
                            SelfHostedPushClient.clearToken()
                            enabled = false
                            status = "Token removed; sync is off."
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(status)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    if lastSuccess > 0 {
                        let last = lastSuccess
                        Text("Last successful database sync: \(Date(timeIntervalSince1970: last).formatted(date: .abbreviated, time: .shortened))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if conflictCount > 0 {
                        Text("Sync conflicts to review: \(conflictCount)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.statusWarning)
                    }
                }
            }
        }
    }

    private func runTest() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let streams = try await SelfHostedPushClient.testConnection()
                status = streams.joined(separator: " · ")
            } catch { status = error.localizedDescription }
        }
    }

    private var ready: Bool {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return url.scheme?.lowercased() == "https" && url.host != nil && SelfHostedPushClient.tokenIsSet
    }

    private func sendNow() {
        busy = true
        Task {
            defer { busy = false }
            var sent: Int?
            var failures: [String] = []
            do { sent = try await SelfHostedPushClient.push(repo: repo) }
            catch { failures.append("NOOP database sync: \(error.localizedDescription)") }
            var outcomes: [String] = []
            if let sent { outcomes.append("Exchanged \(sent) database changes") }
            outcomes += failures
            status = (failures.isEmpty ? "Sync complete. " : "Sync incomplete. ")
                + outcomes.joined(separator: " · ")
        }
    }
}
#endif
