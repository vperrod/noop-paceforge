#if os(iOS)
import SwiftUI
import StrandDesign
import WhoopStore

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
    @State private var dataSummary = "Checking data stored on this iPhone…"
    @State private var dataRows: [SyncedDataRow] = []
    @State private var appleHealthInventory: AppleHealthDataInventory?
    @State private var appleHealthInventoryError: String?

    private struct SyncedDataRow: Identifiable {
        let id: String
        let label: String
        let value: String
    }

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
            StrandCard(padding: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data in NOOP")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("PaceForge data stays separately labeled; it does not replace WHOOP readings.")
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                    Text(dataSummary)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textSecondary)
                    ForEach(dataRows) { row in
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.label)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textSecondary)
                            Spacer(minLength: 12)
                            Text(row.value)
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    if let inventory = appleHealthInventory {
                        HStack {
                            Text("Apple Health records saved on this iPhone")
                                .font(StrandFont.subhead)
                                .foregroundStyle(StrandPalette.textPrimary)
                            Spacer()
                            Button {
                                Task { await refreshAppleHealthInventory() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Refresh Apple Health counts")
                        }
                        Divider().padding(.vertical, 4)
                        Text("\(inventory.dailyDays) days · \(inventory.workouts) workouts · \(inventory.sleepSessions) sleep sessions · \(inventory.hourlyStepEntries) hourly step entries")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                        if let first = inventory.earliestDay, let last = inventory.latestDay {
                            Text(first == last ? first : "Date range: \(first) to \(last)")
                                .font(StrandFont.caption)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        ForEach(Array(appleHealthMetricRows.indices), id: \.self) { index in
                            let metric = appleHealthMetricRows[index]
                            HStack {
                                Text(metric.title)
                                    .font(StrandFont.caption)
                                    .foregroundStyle(StrandPalette.textSecondary)
                                Spacer()
                                Text("\(inventory.metricDays[metric.key, default: 0]) days")
                                    .font(StrandFont.caption.monospacedDigit())
                                    .foregroundStyle(StrandPalette.textPrimary)
                            }
                        }
                        Text("Counts are days with a saved value, not raw samples.")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    } else if let appleHealthInventoryError {
                        Text("Could not read Apple Health counts: \(appleHealthInventoryError)")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.statusWarning)
                    } else {
                        Text("Reading Apple Health counts…")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .task {
            await refreshDataSummary()
            await refreshAppleHealthInventory()
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
            await refreshDataSummary()
            await refreshAppleHealthInventory()
        }
    }

    private var appleHealthMetricRows: [(title: String, key: String)] {
        [
            ("Steps", "steps"),
            ("Resting heart rate", "resting_hr"),
            ("HRV", "hrv"),
            ("Blood oxygen (SpO₂)", "spo2"),
            ("Respiratory rate", "resp_rate"),
            ("Average heart rate", "avg_hr"),
            ("Maximum heart rate", "max_hr"),
            ("Walking heart rate", "walking_hr"),
            ("VO₂ max", "vo2max"),
            ("Active calories", "active_kcal"),
            ("Basal calories", "basal_kcal"),
            ("Sleep", "asleep_min"),
            ("Deep sleep", "deep_min"),
            ("REM sleep", "rem_min"),
            ("Core sleep", "core_min"),
            ("Awake during sleep", "awake_min"),
            ("Time in bed", "in_bed_min"),
            ("Weight", "weight"),
            ("Body fat", "body_fat"),
            ("Lean mass", "lean_mass"),
            ("BMI", "bmi"),
        ]
    }

    @MainActor
    private func refreshAppleHealthInventory() async {
        do {
            guard let store = await repo.storeHandle() else {
                appleHealthInventory = nil
                appleHealthInventoryError = "NOOP's local database is unavailable."
                return
            }
            appleHealthInventory = try await store.appleHealthDataInventory(deviceId: "apple-health")
            appleHealthInventoryError = nil
        } catch {
            appleHealthInventory = nil
            appleHealthInventoryError = error.localizedDescription
        }
    }

    @MainActor
    private func refreshDataSummary() async {
        dataSummary = "Reading the NOOP database on this iPhone…"
        do {
            guard let store = await repo.storeHandle() else {
                dataRows = []
                dataSummary = "NOOP's local database is unavailable."
                return
            }
            let through = Repository.localDayKey(Date())
            let from = "2000-01-01"
            let garmin = try await store.dailyMetrics(deviceId: "paceforge-garmin", from: from, to: through)
            let weight = try await store.metricSeries(deviceId: "paceforge-hume", key: "weight", from: from, to: through)
            let vo2 = try await store.metricSeries(deviceId: "paceforge-garmin", key: "vo2max", from: from, to: through)
            let workouts = try await store.workouts(deviceId: "paceforge", from: 0,
                                                     to: Int(Date().timeIntervalSince1970), limit: 10_000)
            func dated(_ value: String?, _ day: String?) -> String {
                guard let value, let day else { return "Not synced to this iPhone yet" }
                return "\(value) · \(day)"
            }
            let latestSteps = garmin.last(where: { $0.steps != nil })
            let latestWeight = weight.last
            let latestVO2 = vo2.last
            let latestSpo2 = garmin.last(where: { $0.spo2Pct != nil })
            dataRows = [
                SyncedDataRow(id: "steps", label: "Garmin steps", value: dated(latestSteps?.steps.map { $0.formatted() }, latestSteps?.day)),
                SyncedDataRow(id: "spo2", label: "Garmin SpO₂", value: dated(latestSpo2?.spo2Pct.map { String(format: "%.1f%%", $0) }, latestSpo2?.day)),
                SyncedDataRow(id: "vo2", label: "Garmin VO₂ max", value: dated(latestVO2.map { String(format: "%.1f", $0.value) }, latestVO2?.day)),
                SyncedDataRow(id: "weight", label: "Hume weight", value: dated(latestWeight.map { String(format: "%.1f kg", $0.value) }, latestWeight?.day)),
                SyncedDataRow(id: "workouts", label: "PaceForge workouts", value: workouts.count.formatted()),
            ]
            let hasPaceForgeData = !garmin.isEmpty || !weight.isEmpty || !workouts.isEmpty
            dataSummary = hasPaceForgeData
                ? "These are records currently stored in NOOP on this iPhone."
                : "No PaceForge records have reached NOOP on this iPhone yet. Tap Sync now above."
        } catch {
            dataRows = []
            dataSummary = "Could not read the NOOP database: \(error.localizedDescription)"
        }
    }
}
#endif
