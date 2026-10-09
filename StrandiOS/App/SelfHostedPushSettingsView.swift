#if os(iOS)
import SwiftUI
import StrandDesign

/// Opt-in configuration for the NOOP ↔ PaceForge sync.
struct SelfHostedPushSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(SelfHostedPushClient.enabledKey) private var enabled = false
    @AppStorage(SelfHostedPushClient.endpointKey) private var endpoint = ""
    @AppStorage(SelfHostedPushClient.lastSuccessKey) private var lastSuccess = 0.0
    @AppStorage(SelfHostedPushClient.lastActivityFetchKey) private var lastActivityFetch = 0.0
    @State private var token = ""
    @State private var status = "Off. Nothing syncs until you enable this."
    @State private var busy = false

    var body: some View {
        ScreenScaffold(title: "PaceForge sync",
                       subtitle: "Keep NOOP data and PaceForge activities in sync.") {
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
                    Text("NOOP uploads its health data to PaceForge and fetches your recent Garmin activities into a separate PaceForge source. Sync runs when NOOP opens or finishes a strap sync, and you can also run it here.")
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
                        Text("Last successful upload: \(Date(timeIntervalSince1970: last).formatted(date: .abbreviated, time: .shortened))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    if lastActivityFetch > 0 {
                        let last = lastActivityFetch
                        Text("Last successful PaceForge activity fetch: \(Date(timeIntervalSince1970: last).formatted(date: .abbreviated, time: .shortened))")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
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
                status = "Connected. \(streams.count) NOOP streams and PaceForge activities are available."
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
            var received: Int?
            var failures: [String] = []
            do { sent = try await SelfHostedPushClient.push(repo: repo) }
            catch { failures.append("NOOP upload: \(error.localizedDescription)") }
            do { received = try await SelfHostedPushClient.pullActivities(repo: repo) }
            catch { failures.append("PaceForge activities: \(error.localizedDescription)") }
            var outcomes: [String] = []
            if let sent { outcomes.append("Sent \(sent) NOOP records") }
            if let received { outcomes.append("received \(received) PaceForge activities") }
            outcomes += failures
            status = (failures.isEmpty ? "Sync complete. " : "Sync incomplete. ")
                + outcomes.joined(separator: " · ")
        }
    }
}
#endif
