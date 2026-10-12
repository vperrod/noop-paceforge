import SwiftUI
import StrandDesign

/// More > PaceForge: whether body figures stay off the Lock Screen and StandBy widgets. The server's
/// setting (`hide_body_on_lock_screen`) applies until the athlete flips the switch here; the switch writes
/// only the `privacyOverride` choice on this iPhone, never the server. The PaceForge Body tab inside the
/// app is not affected.
struct PFBodyPrivacyToggle: View {
    @State private var choice = PFPrivacy.savedOverride()
    @State private var server = PFSummary.load()?.serverHidesBody

    private var effective: Bool { PFPrivacy.hidesBody(server: server, choice: choice) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { effective }, set: { choose($0) })) {
                Text("Hide body data on the Lock Screen")
                    .font(StrandFont.subhead)
                    .foregroundStyle(StrandPalette.textPrimary)
            }
            .tint(StrandPalette.accent)
            .accessibilityIdentifier("pf-privacy-toggle")
            Text("The body widget then reads \u{201C}Hidden \u{2014} open NOOP\u{201D} instead of your weight and body fat. The Body tab in the app is not affected. " + sourceText)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            if choice != nil {
                Button("Use the server's setting") { choose(nil) }
                    .font(StrandFont.caption.weight(.semibold))
                    .foregroundStyle(StrandPalette.accent)
                    .accessibilityIdentifier("pf-privacy-reset")
            }
        }
    }

    private var sourceText: String {
        if choice != nil { return "This is your choice on this iPhone." }
        switch server {
        case true?: return "Following the server's setting: hide."
        case false?: return "Following the server's setting: show."
        case nil: return "The server did not send a setting, so it is hidden."
        }
    }

    private func choose(_ value: Bool?) {
        if let value {
            UserDefaults.standard.set(value, forKey: PFPrivacy.overrideKey)
        } else {
            UserDefaults.standard.removeObject(forKey: PFPrivacy.overrideKey)
        }
        choice = value
        PFSummaryWriter.applyPrivacy()
    }
}
