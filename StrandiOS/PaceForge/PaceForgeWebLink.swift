import SwiftUI
import StrandDesign

// A row that opens one page of the PaceForge website. The app has no web view that carries its session (the bearer token reads JSON only;
// the pages sign in with a cookie), so the row hands the URL to the system, the way Settings opens its links: Safari, which keeps the
// website's own sign-in. The page is the site root of the saved sync endpoint plus the website's route (`#/training/bike`).

enum PFWebPage {
    /// The website's routes (`web/index.html`: SCREENS, routeHash).
    static let plan = "/training/plan"
    static let strength = "/training/strength"
    static let bike = "/training/bike"

    /// The page's address, or nil when PaceForge sync is not set up.
    static func url(_ route: String) -> URL? {
        guard let endpoint = SelfHostedPushClient.paceForgeCredentials()?.endpoint else { return nil }
        let root = SelfHostedPushClient.paceForgeURL(from: endpoint, path: "")
        guard var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = route
        return components.url
    }
}

/// "Start a programme", "Strength programme", "Ride library": one row to the website page, with a line saying it opens in the browser.
struct PFWebPageRow: View {
    let title: String
    let detail: String
    let icon: String
    let route: String
    let identifier: String
    @Environment(\.openURL) private var openURL

    var body: some View {
        let url = PFWebPage.url(route)
        Button {
            if let url { openURL(url) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(StrandPalette.accent)
                    .frame(width: 26, alignment: .center)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(StrandFont.body).foregroundStyle(StrandPalette.textPrimary)
                    Text(url == nil ? "Set up PaceForge sync in Settings to open it." : detail)
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityIdentifier(identifier)
    }
}
