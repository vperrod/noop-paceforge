#if os(iOS)
import SwiftUI
import StrandDesign

/// iOS navigation shell. macOS uses a `NavigationSplitView` sidebar (`RootView`); on iPhone the
/// natural analogue is a `TabView` with the most-used screens as tabs and everything else under a
/// "More" list. Every screen is the same `StrandDesign`-built view the macOS app uses.
struct RootTabView: View {
    /// #1841: shared with Android by NAME and meaning, not by storage — the two platforms keep their own
    /// stores, exactly as the Clock format setting does.
    ///
    /// Default FALSE here while Android defaults true, and the divergence is deliberate. Apple's forums
    /// report `.tabBarMinimizeBehavior(.onScrollDown)` failing to trigger in tabs built on
    /// `NavigationStack(path:)` — which is every primary tab in this file, bound deliberately so a tab
    /// root can pop and re-scroll. So this may well be inert on our structure, and defaulting ON would
    /// advertise a behaviour that never happens. Off until someone confirms it on an iOS 26 device.
    /// The Coach master switch, under the same `noop.` key Android writes. Default ON, so every install
    /// that shipped with the tab is unchanged.
    ///
    /// Not tab chrome: with this off the AI is off. The tab goes, the Today launcher card goes, and the
    /// daily brief is cancelled, because the brief calls a provider from the BACKGROUND with no UI
    /// attached and would otherwise keep posting AI notifications for a feature the wearer switched off.
    @AppStorage("noop.coachEnabled") private var coachEnabled = true
    @AppStorage("noop.bottomBarAutoHide") private var bottomBarAutoHide = false
    /// The look's rounded floating bar with the coach button replaces the system tab bar. The TabView, its
    /// per-tab NavigationStacks and every selection / re-tap / deep-link path below are unchanged: the system bar
    /// is only hidden, and the floating bar writes through the same `nativeTabSelection` setter. Set `noop.lookTabBar`
    /// to false (a launch argument `-noop.lookTabBar NO` does it) to get the system bar back.
    @AppStorage("noop.lookTabBar") private var lookTabBar = true

    /// The live gym session, owned at the app root — see `LiftSessionController`.
    @EnvironmentObject private var liftSession: LiftSessionController
    /// External entry points must wait until the mandatory first-run gates have completed. The root owns
    /// that state; keeping it explicit here prevents this shell's window-level sheet from covering a gate.
    let homeScreenQuickActionsEnabled: Bool

    @EnvironmentObject private var repo: Repository
    /// Cross-screen navigation requests (e.g. Live → "Manage devices"). Devices isn't a tab — it lives
    /// behind the More list — so a request presents it as a sheet, matching the quick-action screens.
    @EnvironmentObject private var router: NavRouter
    /// The scene-local receiver for actions chosen from NOOP's Home Screen icon menu.
    @EnvironmentObject private var homeScreenQuickActions: HomeScreenQuickActionSceneDelegate

    /// Which quick-action screen the centre FAB is presenting (nil = sheet closed).
    @State private var quickAction: QuickAction?
    /// Presents the Devices manager (pair / switch bands) when a screen asks the shell to open it.
    @State private var showDevices = false
    /// A routed v5 pillar screen (Insights hub / Lab Book / fused record / Rhythm) presented as a sheet
    /// when a hub row deep-links to it via NavRouter. nil = closed.
    @State private var routedPillar: NavRouter.Destination?
    /// Selected tab — bound so tab switches can crossfade (README §Motion: ~240ms opacity swap
    /// between tab roots, calm easing). Defaults to Today.
    @State private var selectedTab: Int = 0
    /// One `NavigationPath` per tab, indexed by tab tag. Re-tapping the already-active tab pops
    /// that tab's stack to its root (#135) by clearing its path — an animated pop that leaves the
    /// root view alive, so an at-root re-tap keeps scroll position and never re-runs `.task`
    /// (#198; the #197 resetID/`.id()` rebuild reset both). Requires the tab roots' first-hop
    /// links to push `TabRoute`/`MoreDestination` VALUES — closure-destination links bypass the path.
    @State private var tabPaths: [NavigationPath] = Array(repeating: NavigationPath(), count: 5)
    /// One scroll-to-top token per tab. Bumped when the user re-taps the active tab while it's ALREADY
    /// at its root — the other half of the iOS convention #197/#198 left unserved (an at-root re-tap was
    /// a no-op). Threaded into each tab's root via `\.scrollToTopSignal`; ScreenScaffold / LiquidTodayView
    /// scroll to their top anchor when their tab's token changes.
    @State private var scrollTop: [Int] = Array(repeating: 0, count: 5)
    /// Native tab selection binding. SwiftUI sends taps on the already-selected item through the
    /// setter, which lets the system tab bar retain the app's refresh / pop-to-root / scroll-to-top
    /// convention without placing a custom hit-testing layer over the platform bar.
    private var nativeTabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { tag in
                if tag == selectedTab {
                    reselectTab(tag)
                } else {
                    selectedTab = tag
                }
            }
        )
    }

    /// Tab ids for the floating bar, in tag order. The ids are the lower-cased titles, which is also what the UI
    /// tests look for (`look-tab-<id>`).
    private static let lookTabs: [LookTabItem] = [
        LookTabItem(id: "today", title: "Today", symbol: "square.grid.2x2"),
        LookTabItem(id: "trends", title: "Trends", symbol: "chart.line.uptrend.xyaxis"),
        // Tab 2 is Sleep, or Day when Settings > Tools > New Day tab (beta) was on at launch (UnifiedDay).
        LookTabItem(id: UnifiedDay.isOn ? "day" : "sleep", title: UnifiedDay.isOn ? "Day" : "Sleep",
                    symbol: UnifiedDay.isOn ? "calendar" : "bed.double"),
        LookTabItem(id: "paceforge", title: "PaceForge", symbol: "figure.run"),
        LookTabItem(id: "more", title: "More", symbol: "ellipsis"),
    ]

    private var lookTabSelection: Binding<String> {
        Binding(
            get: { Self.lookTabs.indices.contains(selectedTab) ? Self.lookTabs[selectedTab].id : "today" },
            set: { id in
                if let tag = Self.lookTabs.firstIndex(where: { $0.id == id }) { nativeTabSelection.wrappedValue = tag }
            }
        )
    }

    private func openPaceForgeToday() {
        PFDeepLink.pending = false
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 3 }
    }

    private func openMyDay() {
        MyDayDeepLink.pending = false
        withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 0 }
        var path = NavigationPath()
        path.append(TabRoute.myDay)
        tabPaths[0] = path
    }

    private func reselectTab(_ tag: Int) {
        Task { await repo.refresh() }
        if !tabPaths[tag].isEmpty {
            tabPaths[tag] = NavigationPath()
        } else {
            scrollTop[tag] += 1
        }
    }

    /// The anywhere-swipe tab-switch drag (2026-07-02). Held as a property so the attachment site can
    /// enable or disable it through a `GestureMask` instead of attaching it conditionally: a conditional
    /// attachment changes view identity, and this condition toggles on every push and pop, which would
    /// rebuild the tab roots underneath it. The same class of rebuild is what #197 caused with an
    /// `.id()` reset and #198 had to undo — it lost scroll position and re-ran `.task`.
    ///
    /// Only a decisive horizontal flick switches tabs, and Today is carved out because it uses
    /// horizontal swipe to change DAYS. Both thresholds are unchanged from the original gesture.
    private var tabSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                // Today (tab 0) uses horizontal swipe to change DAYS, so tab-swipe is off there.
                guard selectedTab != 0 else { return }
                let dx = v.translation.width, dy = v.translation.height
                guard abs(dx) > 60, abs(dx) > abs(dy) * 1.6 else { return }
                let next = min(4, max(0, selectedTab + (dx < 0 ? 1 : -1)))
                if next != selectedTab {
                    withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = next }
                }
            }
    }

    var body: some View {
        let _ = NoopDiag.body("RootTabView")
        // The platform tab bar is intentionally left fully native. iOS 26 supplies Liquid Glass and
        // its dynamic interaction with scrolling content automatically; older supported releases use
        // the corresponding system material and safe-area behaviour from the same TabView.
        TabView(selection: nativeTabSelection) {
            tab(LiquidTodayView(), "Today", "square.grid.2x2", path: $tabPaths[0], scrollSignal: scrollTop[0]).tag(0)
            tab(TrendsView(), "Trends", "chart.line.uptrend.xyaxis", path: $tabPaths[1], scrollSignal: scrollTop[1]).tag(1)
            tab(SleepOrDayRoot(), UnifiedDay.tabTitle, UnifiedDay.tabIcon, path: $tabPaths[2], scrollSignal: scrollTop[2]).tag(2)
            // The PaceForge tab takes Coach's slot (tag 3) and is always present, whatever the Coach
            // master switch says. NOOP's Coach screen is untouched; it opens as a sheet (see .coach below).
            tab(PaceForgeTabView(), "PaceForge", "figure.run", path: $tabPaths[3], scrollSignal: scrollTop[3]).tag(3)
            moreTab(path: $tabPaths[4], scrollSignal: scrollTop[4]).tag(4)
        }
        .tint(StrandPalette.accent)
        .toolbar(lookTabBar ? .hidden : .automatic, for: .tabBar)
        .overlay(alignment: .bottom) {
            if lookTabBar {
                FloatingTabBar(items: Self.lookTabs, selection: lookTabSelection, onCoach: { router.openCoach() })
                    .padding(.bottom, 6)
            }
        }
        // #1841: the same "Hide bar when scrolling" preference Android drives its own bar with. Here the
        // system owns the behaviour — iOS 26's tab bar MINIMISES to a pill on scroll down rather than
        // sliding away entirely, so this is the platform's read of the same intent, not a copy of ours.
        .noopTabBarAutoHide(bottomBarAutoHide)
            // Tab crossfade — README §Motion: ~240ms opacity swap between tab roots, global calm
            // easing cubic-bezier(0.22,1,0.36,1).
            .animation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24), value: selectedTab)
            // The tab on show, for the diagnostics breadcrumbs and the per-screen stall numbers (NoopDiag). The PaceForge
            // tab names its own segment.
            .onChange(of: selectedTab, initial: true) { _, tab in
                if tab != 3 { NoopDiag.screen(Self.lookTabs.indices.contains(tab) ? "tab.\(Self.lookTabs[tab].id)" : "tab.\(tab)") }
            }
            #if DEBUG
            // `-NoopPerfAutopilot` walks the tabs itself (NoopPerfAutopilot).
            .onReceive(NotificationCenter.default.publisher(for: .noopPerfSelectTab)) { note in
                if let tab = note.object as? Int { selectedTab = tab }
            }
            #endif
            // Swipe left/right anywhere to move between tabs (2026-07-02), but ONLY while the current
            // tab is at its root. Attaching this ancestor drag gesture unconditionally defeated the
            // edge-restriction of a pushed NavigationStack screen's native interactive-pop gesture —
            // any More-tab subscreen (Settings, Devices, …) became draggable/rubber-banding from
            // anywhere, not just the left edge (#519). Disabling the recognizer once a push is active,
            // rather than just gating the onEnded action, is what stops the interference: the action
            // never runs early enough, because the recognizer competes during recognition.
            //
            // The mask does that WITHOUT changing view identity. #519 attached the gesture through a
            // conditional ViewModifier, which put the two states in separate _ConditionalContent
            // branches — and since this condition toggles on every push and pop, each navigation
            // rebuilt the whole TabView subtree and could reset @State inside the tab roots (scroll
            // offsets, chart ranges, expanded sections). `including:` keeps one view type in both
            // states, so nothing is torn down.
            //
            // The mask MUST be `.subviews`, not `.none`. `.subviews` means "enable the subview
            // hierarchy's gestures, disable the added one" — exactly this requirement. `.none` disables
            // the subview hierarchy TOO, which on a pushed screen would take out scrolling, taps and the
            // interactive-pop itself: far worse than the bug being fixed.
            .simultaneousGesture(tabSwipeGesture,
                                 including: tabPaths[selectedTab].isEmpty ? .all : .subviews)
        .task {
            await repo.refresh()
            // Backup & Sync: on-launch catch-up (see RootView). Detached + utility priority so a
            // 100MB+ whole-DB ZIP never blocks startup; gated on the auto toggle (default OFF). (Must-fix #4.)
            let backupRepo = repo
            Task.detached(priority: .utility) {
                await FolderBackup.catchUpIfDue(checkpoint: { await backupRepo.checkpointForBackup() })
            }
        }
        // Quick-action sheet presents with the calm easing (~0.42s) per the README sheet spec —
        // the easing is applied where `quickAction` is set (see `presentQuickAction`), keeping the
        // animation scoped to the sheet rather than the whole shell.
        .sheet(item: $quickAction) { action in
            quickActionDestination(action)
        }
        // Widgets, the PaceForge brief notification and the Control Center control land on PaceForge > Today.
        .onReceive(NotificationCenter.default.publisher(for: .pfOpenToday)) { _ in openPaceForgeToday() }
        .onAppear { if PFDeepLink.pending { openPaceForgeToday() } }
        // `noop://myday` and PaceForge's "Open My Day" button land on the Today tab's My Day.
        .onReceive(NotificationCenter.default.publisher(for: .myDayOpen)) { _ in openMyDay() }
        .onAppear { if MyDayDeepLink.pending { openMyDay() } }
        #if DEBUG
        // `-CoachFixture` (UI tests): open the connected, made-up Coach straight away.
        .onAppear { if CoachUITestFixture.isActive { router.openCoach() } }
        #endif
        // Live's "Manage devices" affordance (and any future cross-screen link to Devices) routes here:
        // present the Devices manager in its own nav stack, the same way the quick-action screens do.
        .sheet(isPresented: $showDevices) {
            devicesScreen
        }
        // v5 pillar deep-links (Insights hub / Lab Book / fused record / Rhythm) present as a sheet in
        // their own nav stack — the same idiom the quick-action + Devices screens use on iPhone.
        .sheet(item: $routedPillar) { dest in
            pillarScreen(dest)
        }
        // Honour a router request: Devices keeps its dedicated sheet; the v5 pillars route through the
        // shared pillar sheet. Cleared so the same tap can fire again later.
        .onChange(of: router.requestedDestination) { _, dest in
            switch dest {
            case .devices:
                showDevices = true
                router.requestedDestination = nil
            case .insightsHub, .labBook, .fusedRecord, .rhythm, .alarms:
                routedPillar = dest
                router.requestedDestination = nil
            case .coach:
                // K3: Coach is now a top-level tab (tag 3) — switch to it directly instead of
                // presenting it as a pillar sheet.
                //
                // Guarded on the master switch, because this route is reachable with Coach OFF. A brief
                // notification already sitting in Notification Centre still calls `openCoach()` when it is
                // tapped (StrandApp wires `onCoachBriefTapped` to it), and with no tab claiming tag 3 the
                // wearer would land on a BLANK tab. Dropping the request leaves them where they were, which
                // is the honest answer for a feature that is switched off.
                guard coachEnabled else {
                    router.requestedDestination = nil
                    break
                }
                // Tag 3 is the PaceForge tab now, so Coach opens as a sheet like the other pillars.
                routedPillar = dest
                router.requestedDestination = nil
            case .trends:
                // Trends is a primary tab on iPhone (not a pillar sheet) — switch to it.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 1 }
                router.requestedDestination = nil
            case .activeWorkout:
                // The Today active-workout indicator opens Live through the quick-action Live sheet; once
                // it's up, LiveView consumes the one-shot `presentActiveWorkout` flag and presents the
                // in-exercise screen. Calm sheet easing, matching the other quick-action presents.
                withAnimation(Self.sheetEase) { quickAction = .live }
                router.requestedDestination = nil
            case .liveSession:
                // Live Sessions is presented from Today's own Start entry (a cover, not a routed sheet),
                // so a deep-link lands on the Today tab where that entry lives.
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 0 }
                router.requestedDestination = nil
            case .journal:
                // The #627 Today journal widget opens the journal through the quick-action Journal sheet
                // (the Insights screen on its Journal section), matching the "Log journal" action. Calm sheet easing.
                withAnimation(Self.sheetEase) { quickAction = .journal }
                router.requestedDestination = nil
            case .sleep:
                // Sleep is a tab: a link elsewhere switches to it (and leaves the tab it came from at its root) rather than
                // pushing a second Sleep screen over that tab.
                tabPaths[selectedTab] = NavigationPath()
                // With the Day tab on, tab 2 is Day: land on its Sleep chip.
                if UnifiedDay.isOn { UserDefaults.standard.set(DayChip.sleep.rawValue, forKey: DayChip.storageKey) }
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { selectedTab = 2 }
                router.requestedDestination = nil
            case nil:
                break
            }
        }
        // A screen's top-bar "+" routes here: open the quick-action sheet, then clear the flag.
        .onChange(of: router.quickActionsRequested) { _, req in
            if req {
                withAnimation(Self.sheetEase) { quickAction = .menu }
                router.quickActionsRequested = false
            }
        }
        // A cold-launch selection is already pending when this shell appears; a warm selection arrives
        // through the change callback. Both route through the same screens as the centre FAB.
        .onAppear {
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChange(of: homeScreenQuickActions.pendingAction) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        .onChange(of: homeScreenQuickActionsEnabled) { _, _ in
            presentPendingHomeScreenQuickActionIfPossible()
        }
        // The running gym session, reachable from ANY tab. It sits above the tab bar rather than
        // inside the Lift Log screen, because a workout outlives whichever screen you wandered to —
        // and because swiping the sheet away must minimise the session, not end it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if liftSession.isActive {
                LiftSessionBar()
                    .padding(.horizontal, 14)
                    // Clear the floating tab bar with the same constant every screen uses, or the
                    // session bar sits on top of the tab labels.
                    .padding(.bottom, NoopMetrics.tabBarClearance)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: liftSession.isActive)
        // A session left running by a previous launch is back before this view exists
        // (`LiftSessionController.resumeSaved`, from `StrandiOSApp.init`), as the BAR — not as a sheet
        // thrown in the user's face; they open it when they want it.
        .sheet(isPresented: $liftSession.isPresented) {
            LiftSessionView { }
        }
    }

    /// Mandatory launch gates defer an external action. Once the shell is available, an explicit Home
    /// Screen choice supersedes any ordinary shell sheet; choosing the already-open destination simply
    /// consumes the request and leaves that screen in place.
    private func presentPendingHomeScreenQuickActionIfPossible() {
        guard homeScreenQuickActionsEnabled,
              let action = homeScreenQuickActions.pendingAction else { return }

        if let segment = action.paceForgeSegment {
            homeScreenQuickActions.consume(action)
            PFDeepLink.open(segment)
            return
        }
        let destination: QuickAction = switch action {
        case .liveHeartRate: .live
        case .startWorkout: .workout
        case .logJournal: .journal
        case .breathe: .breathe
        case .paceForgeToday, .paceForgeWeek, .paceForgeCoach: .live // handled above
        }
        homeScreenQuickActions.consume(action)
        withAnimation(Self.sheetEase) {
            showDevices = false
            routedPillar = nil
            quickAction = destination
        }
    }

    /// A routed v5 pillar screen wrapped in its own nav stack + Done button (mirrors `quickScreen`).
    @ViewBuilder
    private func pillarScreen(_ dest: NavRouter.Destination) -> some View {
        NavigationStack {
            Group {
                switch dest {
                case .insightsHub: InsightsHomeView(initial: .moves)
                case .labBook: LabBookView()
                case .fusedRecord: FusedRecordHost()
                case .rhythm: RhythmHost(onClose: { routedPillar = nil })
                case .devices: DevicesView()
                // .trends is never presented as a pillar sheet on iPhone (it's a primary tab — the
                // requestedDestination handler switches `selectedTab` instead), but the switch must stay
                // exhaustive. Fall back to Trends inside the sheet host if it ever arrives here.
                case .trends: TrendsView()
                // .activeWorkout routes through the quick-action Live sheet (handled above); this keeps the
                // switch exhaustive and falls back to Live if it ever reaches the pillar host.
                case .activeWorkout: LiveView()
                // .liveSession routes to the Today tab (handled above — its Start entry owns the cover);
                // this keeps the switch exhaustive and falls back to Today if it ever reaches the host.
                case .liveSession: LiquidTodayView()
                // .journal opens through the quick-action Journal sheet (handled above); this keeps the
                // switch exhaustive and falls back to the journal's Insights host if it ever reaches here.
                case .journal: InsightsHomeView(initial: .journal)
                // .sleep switches to the Sleep tab (handled above); this keeps the switch exhaustive.
                case .sleep: SleepView()
                // .coach switches to the Coach tab (handled above — the morning-brief tap-through and the
                // #1862 launcher both arrive that way, the launcher's question riding on
                // `AICoachEngine.pendingPrompt`); this keeps the switch exhaustive and falls back to Coach if
                // it ever reaches the host.
                case .coach: CoachView()
                case .alarms: SmartAlarmView()
                }
            }
            // The Trends/Today fallbacks above emit TabRoute value pushes (#198), which need a
            // destination registered in THIS sheet's stack to resolve.
            .tabRouteDestinations()
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            // #1027: same fix as quickScreen — the pillar screens draw the full-bleed liquid sky, so a
            // transparent nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { routedPillar = nil }
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    /// Calm-easing curve (cubic-bezier(0.22,1,0.36,1)) at the README sheet-present duration.
    private static let sheetEase = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.42)

    // MARK: - Quick-action sheet

    /// Routes a chosen quick action to the existing screen, or shows the action menu itself.
    @ViewBuilder
    private func quickActionDestination(_ action: QuickAction) -> some View {
        switch action {
        case .menu:
            QuickActionSheet { picked in
                // Swap the menu for the chosen destination on the next runloop so the sheet
                // re-presents cleanly (avoids dismiss/re-present races). Calm easing on re-present.
                quickAction = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(Self.sheetEase) { quickAction = picked }
                }
            }
            .presentationDetents([.height(412)])
            .presentationDragIndicator(.hidden)
        case .live:
            quickScreen(LiveView())
        case .workout:
            quickScreen(WorkoutsView())
        case .journal:
            quickScreen(InsightsHomeView(initial: .journal))
        case .breathe:
            quickScreen(BreathingView())
        case .intervals:
            quickScreen(IntervalTimerView())
        }
    }

    /// Wraps a routed quick-action screen in its own nav stack so it has a title bar + the
    /// shared surface background, matching how the More-tab links present these same views.
    private func quickScreen<V: View>(_ view: V) -> some View {
        NavigationStack {
            view
                // The Reports entries on the Insights screen push TabRoute values, which this sheet's own stack must resolve.
                .tabRouteDestinations()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: these screens draw a full-bleed liquid sky (ScreenScaffold topBackground) that runs
                // edge-to-edge under a transparent bar — exactly how the tab roots present it. An OPAQUE
                // surfaceBase toolbar background sat on top of that sky and, as the content scrolled up, its
                // extended status-bar band CLIPPED the sky + the in-content header ("Live Body Console").
                // Hiding the bar background lets the sky stay continuous under the floating Done button.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { quickAction = nil }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    /// The Devices manager wrapped in its own nav stack + Done button (mirrors `quickScreen`, but
    /// dismisses the dedicated `showDevices` sheet rather than the quick-action item).
    private var devicesScreen: some View {
        NavigationStack {
            DevicesView()
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .navigationBarTitleDisplayMode(.inline)
                // #1027: same fix as quickScreen — Devices draws the full-bleed liquid sky, so a transparent
                // nav bar keeps it edge-to-edge instead of an opaque band clipping the top on scroll.
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showDevices = false }
                            .foregroundStyle(StrandPalette.accent)
                    }
                }
        }
    }

    private func tab<V: View>(_ view: V, _ title: LocalizedStringKey, _ icon: String,
                              path: Binding<NavigationPath>, scrollSignal: Int) -> some View {
        // Each primary tab gets its OWN NavigationStack so the in-content NavigationLinks (e.g. the Today
        // dashboard card rows) both navigate AND render opaque. An ORPHANED NavigationLink (no
        // NavigationStack ancestor) renders its whole label in a disabled/translucent state — that was
        // washing the Today cards over the hero scene and dimming their text to grey (2026-06-23).
        // The root view hides the system nav bar (each screen draws its own in-content header); pushed
        // detail screens get their own nav bar + back button. The stack is bound to the tab's path so a
        // re-tap of the active tab can pop it to the root (#135/#198); the roots' first-hop links push
        // TabRoute values, registered here ONCE per stack (a double registration double-pushes, #38).
        NavigationStack(path: path) {
            view
                .background(StrandPalette.surfaceBase.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .tabRouteDestinations()
        }
        // Drive this tab's root scroll-to-top on an at-root re-tap (#198 follow-up); read by ScreenScaffold
        // / LiquidTodayView inside. Only THIS tab's token changes on its reselect, so the others don't scroll.
        .environment(\.scrollToTopSignal, scrollSignal)
        // The system bar is hidden from inside each tab's stack: on the TabView itself the modifier does nothing
        // on iOS 26, and the glass bar showed behind the look's floating bar.
        .toolbar(lookTabBar ? .hidden : .automatic, for: .tabBar)
        .tabItem { Label(title, systemImage: icon) }
    }

    // The "More" tab is the app's index of everything that is not a tab. Eleven rows in three groups, all visible at rest: Insights
    // (one screen with its sections, Reports among them), Explore and Compare; the body screens; and Data and Settings. Live, Workouts,
    // Breathe and Intervals are in the quick-action sheet; Test Centre, Automations, Siri & Shortcuts and Power saving are in Settings;
    // Fused, Apple Health, Mi Band, Data Sources, Backup & Sync, Shortcuts Export, PaceForge sync and NOOP Limitations are in Data.
    private func moreTab(path: Binding<NavigationPath>, scrollSignal: Int) -> some View {
        NavigationStack(path: path) {
            ScreenScaffold(title: "More", subtitle: "Everything else, two taps away",
                           onRefresh: { await repo.refresh() },
                           topBackground: liquidScaffoldSky()) {
                IndexSection("Insights") {
                    IndexRow("Insights", "lightbulb.fill", MoreDestination.insights, id: "more-row-insights")
                    IndexRow("Explore", "square.grid.2x2.fill", MoreDestination.explore, id: "more-row-explore")
                    IndexRow("Compare", "rectangle.split.2x1.fill", MoreDestination.compare, id: "more-row-compare")
                }
                IndexSection("Body") {
                    IndexRow("Lift Log", "dumbbell.fill", MoreDestination.liftLog, id: "more-row-liftlog")
                    IndexRow("Health", "heart.text.square.fill", MoreDestination.health, id: "more-row-health")
                    IndexRow("Stress", "bolt.heart.fill", MoreDestination.stress, id: "more-row-stress")
                    IndexRow("Lab Book", "books.vertical.fill", MoreDestination.labBook, id: "more-row-labbook")
                    // Experimental beat-to-beat regularity visualization: self-gates on its own consent.
                    IndexRow("Rhythm", "waveform.path", MoreDestination.rhythm, id: "more-row-rhythm")
                    // #805/#811: Alarms is its own row (the single "Alarms" entry the v7.3.1 #766 consolidation made), routed to
                    // SmartAlarmView, the cross-platform surface. Notifications is macOS-only (it picks which Mac apps tap your
                    // wrist via NSWorkspace); iPhone's wrist-alert controls are on the Automations screen, now inside Settings.
                    IndexRow("Alarms", "alarm.fill", MoreDestination.alarms, id: "more-row-alarms")
                }
                IndexSection("App") {
                    IndexRow("Data", "externaldrive.fill", MoreDestination.data, id: "more-row-data")
                    IndexRow("Settings", "gearshape.fill", MoreDestination.settings, id: "more-row-settings")
                }
            }
            // The rows push MoreDestination VALUES so a re-tap of the More tab can pop them off the bound path (#135/#198).
            // Each destination keeps the per-screen wrapper the rows used to apply inline (surfaceBase background, inline title
            // bar, hidden bar background): #1027, a pushed sky-scaffold screen draws a full-bleed liquid sky, and an opaque
            // surfaceBase nav-bar band sat over it and clipped the top on scroll. The screen's own container identifier is
            // `screen-<destination>`, which the navigation tests look for.
            .navigationDestination(for: MoreDestination.self) { route in
                route.destination
                    .containerIdentifier("screen-\(route.rawValue)")
                    .background(StrandPalette.surfaceBase.ignoresSafeArea())
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            // Screens pushed from inside a More destination (the Reports entries, the streak chip's Highlights) push TabRoute
            // values, which this stack must resolve like every tab's.
            .tabRouteDestinations()
        }
        // Scroll the More index to the top on an at-root re-tap (#198 follow-up); read by its ScreenScaffold.
        .environment(\.scrollToTopSignal, scrollSignal)
        .toolbar(lookTabBar ? .hidden : .automatic, for: .tabBar)
        .tabItem { Label("More", systemImage: "ellipsis") }
    }
}

/// The root of tab 2: the Sleep screen (build 479), or the Day screen when the New Day tab (beta) was on at launch. The choice is
/// fixed for the life of the process, so the tab never changes identity while the app runs.
private struct SleepOrDayRoot: View {
    var body: some View {
        if UnifiedDay.isOn {
            DayHostView()
        } else {
            SleepView()
        }
    }
}

/// Every screen the More index links to, as a `Hashable` value the tab's `NavigationPath` can carry
/// (#198): a closure-destination push would bypass the path and be un-poppable on tab re-tap. The
/// per-screen chrome the old inline links applied lives at the single `navigationDestination(for:)`
/// registration in `moreTab`.
private enum MoreDestination: String, Hashable {
    case insights, explore, compare
    case liftLog, health, stress, labBook, rhythm, alarms
    case data, settings

    @ViewBuilder var destination: some View {
        switch self {
        case .insights:        InsightsHomeView()
        case .explore:         MetricExplorerView()
        case .compare:         CompareView()
        case .liftLog:         LiftLogView()
        case .health:          HealthView()
        case .stress:          StressView()
        case .labBook:         LabBookView()
        case .rhythm:          RhythmHost()
        case .alarms:          SmartAlarmView()
        case .data:            DataHubView()
        case .settings:        SettingsView()
        }
    }
}

// MARK: - Quick actions (centre FAB)

/// The destinations the centre FAB can present. `.menu` is the action sheet itself; the rest
/// route to existing screens. `Identifiable` so it drives `.sheet(item:)`.
private enum QuickAction: Int, Identifiable {
    case menu, live, workout, journal, breathe, intervals
    var id: Int { rawValue }
}

/// The bottom sheet of quick actions presented by the centre FAB. Spec bottom sheet: surfaceOverlay
/// fill, gold hairline top edge, grab handle, three flat action rows that route to existing screens.
private struct QuickActionSheet: View {
    /// Called with the picked destination (the host swaps the menu for that screen).
    let onPick: (QuickAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle (36×4) in the slate hairline tone.
            Capsule()
                .fill(StrandPalette.hairlineStrong)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            Text("QUICK ACTIONS")
                .font(StrandFont.overline)
                .tracking(1.6)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            VStack(spacing: 8) {
                row("Live HR", icon: "waveform.path.ecg", tint: StrandPalette.metricRose, id: "live") { onPick(.live) }
                row("Start workout", icon: "figure.run", tint: StrandPalette.effortColor, id: "workout") { onPick(.workout) }
                row("Log journal", icon: "square.and.pencil", tint: StrandPalette.accent, id: "journal") { onPick(.journal) }
                row("Breathe", icon: "wind", tint: StrandPalette.restColor, id: "breathe") { onPick(.breathe) }
                row("Intervals", icon: "timer", tint: StrandPalette.metricCyan, id: "intervals") { onPick(.intervals) }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            NoopChromeSurface()
                .overlay(alignment: .top) {
                    // Gold hairline top edge per the bottom-sheet spec.
                    Rectangle()
                        .fill(StrandPalette.gold.opacity(0.35))
                        .frame(height: 1)
                }
                .ignoresSafeArea()
        )
    }

    /// One flat action row: hued line-icon tile + title, inset surface, hairline border.
    private func row(_ title: LocalizedStringKey, icon: String, tint: Color, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(StrandPalette.surfaceInset))
                Text(title)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(NoopPanelSurface(cornerRadius: 14))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("quick-action-\(id)")
    }
}

#endif

/// #1841: apply the iOS 26 tab-bar minimise behaviour, doing nothing on older systems.
///
/// The availability branch is deliberately the ONLY branch. `RootTabView` already documents what happens
/// when a condition that flips at runtime wraps this `TabView`: #519 put two states in separate
/// `_ConditionalContent` branches, and every navigation rebuilt the whole subtree, resetting `@State`
/// inside the tab roots — scroll offsets, chart ranges, expanded sections.
///
/// So the preference must NOT select between branches. It selects the modifier's ARGUMENT, while the
/// availability check — fixed for the life of the process — is what picks a branch. Toggling the setting
/// changes a value, never the view's identity.
extension View {
    @ViewBuilder
    func noopTabBarAutoHide(_ enabled: Bool) -> some View {
        if #available(iOS 26.0, *) {
            // `.onScrollDown` minimises to a pill on downward scroll; `.never` pins it fully visible.
            self.tabBarMinimizeBehavior(enabled ? .onScrollDown : .never)
        } else {
            self
        }
    }
}
