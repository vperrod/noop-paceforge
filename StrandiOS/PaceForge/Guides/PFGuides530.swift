import SwiftUI
import StrandDesign

// Short guides: what to press, in order, to get one common thing done (`GET guides`). Each step that names a control the app has gets a
// button that goes to it; a step that names nothing the app has is plain text. Where each target is on the iPhone is
// `PFGuideTarget.resolve` (PaceForgeOutcomeGuides.swift, unit-tested). Reached from "How your plan is built".

extension Notification.Name {
    /// A guide step asked for a tab the Plan section cannot reach itself (Health's Sleep chip, Train's Strength or Workouts chip, the Lab Book).
    /// The object is the `PFGuideTarget` raw value; the tab shell switches to it.
    static let pfOpenGuideTarget = Notification.Name("pf.guides.openTarget")
}

/// Goes to a guide step's control. A sheet over the Plan tab closes first, so what it opens is not hidden behind it.
@MainActor
enum PFGuideLink530 {
    static func open(_ target: PFGuideTarget) {
        PFPlan529Router.shared.sheet = nil
        // The sheet has to finish closing before the tab underneath changes or the Coach opens over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            switch target {
            case .planWeek: PFDeepLink529.open(.chip(.week))
            case .planSeason: PFDeepLink529.open(.chip(.season))
            case .planReports: PFDeepLink529.open(.chip(.reports))
            case .planSettings: PFDeepLink529.open(.sheet(.planSettings))
            case .coach: PFDeepLink.open(.coach)
            case .healthSleep, .trainWorkouts, .trainStrength, .labBook:
                NotificationCenter.default.post(name: .pfOpenGuideTarget, object: target.rawValue)
            }
        }
    }
}

/// The row under "How your plan is built" that opens the guides.
struct PFGuidesLinkRow530: View {
    var body: some View {
        NavigationLink {
            PFGuidesList530()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Guides")
                        .font(LookFont.text(15, weight: .semibold))
                        .foregroundStyle(NoopLook.textPrimary)
                    Text("Short steps for fixing sleep, changing the plan, correcting a workout, finding reports and importing a CSV.")
                        .font(LookFont.text(12.5))
                        .foregroundStyle(NoopLook.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NoopLook.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .planCard529()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("guides530-open")
    }
}

/// The list of guides.
struct PFGuidesList530: View {
    @State private var guides: [PFGuide] = []
    @State private var state = PFDocPlaceholder529.Kind.loading

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if guides.isEmpty {
                PFDocPlaceholder529(kind: state, emptyTitle: "No guides yet",
                                    emptyText: "PaceForge has not published its guides to this phone yet.",
                                    failedText: "PaceForge could not be reached, so the guides are not on this phone yet.",
                                    retry: { Task { await load() } })
            } else {
                Text("Short steps for the things people ask about most. Each step has a button that takes you to the control.")
                    .font(LookFont.text(13.5))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(guides) { guide in
                    NavigationLink {
                        PFGuideDetail530(guide: guide)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(guide.title)
                                .font(LookFont.text(15, weight: .semibold))
                                .foregroundStyle(NoopLook.textPrimary)
                                .multilineTextAlignment(.leading)
                            if !guide.summary.isEmpty {
                                Text(guide.summary)
                                    .font(LookFont.text(13))
                                    .foregroundStyle(NoopLook.textSecondary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .planCard529()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("guide530-\(guide.id)")
                }
            }
        }
        .planScreen529(title: "Guides", identifier: "guides530-list")
        .task { await load() }
    }

    @MainActor private func load() async {
        guard PFAPI.isConfigured else {
            state = .empty
            return
        }
        let fetched = await PFAPI.fetchDoc("api/guides")
        guard let data = fetched.data else {
            state = fetched.failed ? .failed : .empty
            return
        }
        let parsed = PFGuides.parse(PFJ(data: data))
        guides = parsed
        state = .empty
    }
}

/// One guide: its numbered steps.
struct PFGuideDetail530: View {
    let guide: PFGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !guide.summary.isEmpty {
                Text(guide.summary)
                    .font(LookFont.text(14))
                    .foregroundStyle(NoopLook.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(guide.steps) { step in stepCard(step) }
        }
        .planScreen529(title: guide.title, identifier: "guide530-detail-\(guide.id)")
    }

    private func stepCard(_ step: PFGuide.Step) -> some View {
        let target = PFGuideTarget.resolve(step)
        return VStack(alignment: .leading, spacing: 8) {
            PFOver529(text: "Step \(step.index + 1)")
            Text(step.text)
                .font(LookFont.text(14.5))
                .foregroundStyle(NoopLook.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let target {
                Button {
                    PFGuideLink530.open(target)
                } label: {
                    Text(target.title)
                        .font(LookFont.text(14, weight: .semibold))
                        .foregroundStyle(StrandPalette.accent)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("guide530-step-\(guide.id)-\(step.index)")
            }
        }
        .planCard529()
    }
}
