#if os(iOS)
import SwiftUI
import StrandDesign

/// Opt-in configuration for the existing one-way NOOP push protocol.
struct SelfHostedPushSettingsView: View {
    @EnvironmentObject private var repo: Repository
    @AppStorage(SelfHostedPushClient.enabledKey) private var enabled = false
    @AppStorage(SelfHostedPushClient.endpointKey) private var endpoint = ""
    @AppStorage(SelfHostedPushClient.lastSuccessKey) private var lastSuccess = 0.0
    @State private var token = ""
    @State private var status = "Off. Nothing is sent until you enable this."
    @State private var busy = false

    var body: some View {
        ScreenScaffold(title: "PaceForge push",
                       subtitle: "Send your NOOP data directly to your PaceForge server.") {
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
                    Text("One-way: NOOP sends its supported health streams to the endpoint you enter. PaceForge never sends commands or settings back to NOOP. Uploads run separately from strap sync and retry when the app next runs.")
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
                        Button("Send now") { sendNow() }
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
                status = "Connected. PaceForge accepts \(streams.count) streams."
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
            do {
                let count = try await SelfHostedPushClient.push(repo: repo)
                status = count == 0 ? "Up to date." : "Accepted \(count) records."
            } catch { status = error.localizedDescription }
        }
    }
}
#endif
