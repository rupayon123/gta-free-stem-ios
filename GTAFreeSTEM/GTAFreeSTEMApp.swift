import BackgroundTasks
import SwiftData
import SwiftUI

enum AppRuntime {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Lets screenshot QA hold each genuine readiness milestone long enough to
    /// inspect it. Production builds compile the pause out completely.
    static func pauseForLaunchReview() async {
#if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-review-launch") else { return }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
#endif
    }
}

@main
struct GTAFreeSTEMApp: App {
    nonisolated private static let appRefreshIdentifier = "com.rupayonhaldar.gtafreestem.hunt.refresh"
    nonisolated private static let refreshMinInterval: TimeInterval = 60 * 60 * 3
    nonisolated private static let scheduleMinInterval: TimeInterval = 60 * 15
    nonisolated private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            OpportunityCacheRecord.self,
            SavedHuntRecord.self,
            SeenOpportunityRecord.self,
            SavedOpportunityRecord.self
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to initialize shared model container: \(error)")
        }
    }()
    private static let scheduleState = AppRefreshScheduleState()

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var session = SessionStore()
    @StateObject private var opportunities = OpportunityStore(api: APIClient())
    @State private var isShowingLaunchExperience = !AppRuntime.isRunningTests
    @State private var launchProgress = 0.0

    init() {
#if os(iOS) && !targetEnvironment(macCatalyst)
        WatchSavedOpportunitySync.shared.configure(container: Self.sharedModelContainer)
#endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Match the launch storyboard and cover both branches so the
                // handoff can never expose the window's default white surface.
                Brand.ice
                    .ignoresSafeArea()

                // Keep the launch art and the interactive app mutually exclusive.
                // A cross-fade here let a partially loaded home screen show through
                // the loader on slower devices.
                if isShowingLaunchExperience {
                    AppLaunchExperience(
                        title: session.text("brand"),
                        mission: session.text("mission"),
                        loadingText: session.text("preparingOpportunities"),
                        progress: launchProgress
                    )
                } else {
                    ContentView()
                        .environmentObject(session)
                        .environmentObject(opportunities)
                        .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
                        .environment(\.layoutDirection, session.language.layoutDirection)
                        .preferredColorScheme(session.colorScheme)
                        .modelContainer(Self.sharedModelContainer)
                }
            }
            .task {
                guard isShowingLaunchExperience else { return }
                withAnimation(.easeOut(duration: 0.24)) {
                    launchProgress = 0.16
                }
                await Task.yield()
                await AppRuntime.pauseForLaunchReview()

                // Prepare the best available local snapshot before handoff. A
                // bundled or saved snapshot is immediately usable; if both are
                // unavailable, the interactive view owns its honest loading or
                // error state while it attempts the live refresh.
                let context = ModelContext(Self.sharedModelContainer)
                withAnimation(.easeInOut(duration: 0.24)) {
                    launchProgress = 0.38
                }
                await AppRuntime.pauseForLaunchReview()
                let initialSnapshotIsReady = await opportunities.prepareInitialSnapshot(cache: context)
#if os(iOS) && !targetEnvironment(macCatalyst)
                WatchSavedOpportunitySync.shared.sync(in: context)
#endif
                guard !Task.isCancelled else { return }

                // A damaged or missing bundled file must not trap the launch
                // screen behind network timeouts. The interactive shell owns its
                // normal live refresh and presents its honest empty/error state.
                withAnimation(.easeInOut(duration: 0.32)) {
                    launchProgress = initialSnapshotIsReady ? 0.90 : 0.84
                }
                await Task.yield()
                await AppRuntime.pauseForLaunchReview()
                guard !Task.isCancelled else { return }

                // Completion is tied to the real readiness checkpoint above; the
                // bar never loops or restarts independently of app work.
                withAnimation(.easeOut(duration: 0.26)) {
                    launchProgress = 1
                }
                // Let the completed state register before the prepared app takes
                // over. Reduced Motion skips the decorative interpolation.
                try? await Task.sleep(nanoseconds: reduceMotion ? 35_000_000 : 600_000_000)
                guard !Task.isCancelled else { return }
                isShowingLaunchExperience = false
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    Self.scheduleAppRefresh()
                } else if phase == .active {
#if os(iOS) && !targetEnvironment(macCatalyst)
                    WatchSavedOpportunitySync.shared.sync(in: ModelContext(Self.sharedModelContainer))
#endif
                }
            }
        }
        .backgroundTask(.appRefresh(Self.appRefreshIdentifier)) {
            let context = ModelContext(Self.sharedModelContainer)
            await opportunities.refresh(cache: context, notifyOnNewMatches: true)
            Self.scheduleAppRefresh()
        }
    }

    nonisolated private static func scheduleAppRefresh() {
        let now = Date()
        Task {
            guard await Self.scheduleState.claimSubmission(now: now, minimumInterval: Self.scheduleMinInterval) else {
                return
            }

            let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
            request.earliestBeginDate = Date(timeIntervalSinceNow: refreshMinInterval)
            do {
                try BGTaskScheduler.shared.submit(request)
            } catch {
                await Self.scheduleState.clearSubmission(at: now)
                return
            }
        }
    }
}

private struct AppLaunchExperience: View {
    private static let heroLogoSize: CGFloat = 220

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sciencePresented = false
    @State private var detailsPresented = false
    @State private var animationStart = Date()
    @State private var displayedProgress = 0.0

    let title: String
    let mission: String
    let loadingText: String
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let usesHorizontalLayout = proxy.size.width > proxy.size.height
            let horizontalInset = max(20, max(proxy.safeAreaInsets.leading, proxy.safeAreaInsets.trailing) + 14)
            let verticalInset = max(14, max(proxy.safeAreaInsets.top, proxy.safeAreaInsets.bottom) + 8)
            let availableWidth = max(260, proxy.size.width - (horizontalInset * 2))
            let availableHeight = max(240, proxy.size.height - (verticalInset * 2))
            let fieldDiameter = usesHorizontalLayout
                ? min(300, max(210, min(availableHeight - 8, availableWidth * 0.43)))
                : min(420, max(286, min(availableWidth, availableHeight * 0.54)))
            let logoSize = usesHorizontalLayout
                ? min(224, max(176, fieldDiameter * 0.72))
                : min(280, max(Self.heroLogoSize, fieldDiameter * 0.72))
            let panelWidth = min(344, usesHorizontalLayout ? availableWidth * 0.46 : availableWidth)

            ZStack {
                // Match the storyboard exactly before any animated layer is
                // introduced, so launch reads as one continuous experience.
                Brand.ice
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [Brand.ice, Brand.mintFoam.opacity(0.82), Brand.cream],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .opacity(sciencePresented ? 1 : 0)

                Circle()
                    .fill(Brand.sun.opacity(0.18))
                    .frame(width: 220, height: 220)
                    .blur(radius: 24)
                    .position(x: proxy.size.width - 22, y: 40)
                    .opacity(sciencePresented ? 1 : 0)

                Circle()
                    .fill(Brand.coral.opacity(0.09))
                    .frame(width: 196, height: 196)
                    .blur(radius: 26)
                    .position(x: 8, y: proxy.size.height - 24)
                    .opacity(sciencePresented ? 1 : 0)

                Group {
                    if usesHorizontalLayout {
                        HStack(spacing: 22) {
                            launchHero(fieldDiameter: fieldDiameter, logoSize: logoSize)

                            LaunchProgressPanel(
                                loadingText: loadingText,
                                progress: displayedProgress
                            )
                            .frame(width: panelWidth)
                            .offset(x: detailsPresented ? 0 : 10)
                            .opacity(detailsPresented ? 1 : 0)
                        }
                    } else {
                        VStack(spacing: 14) {
                            launchHero(fieldDiameter: fieldDiameter, logoSize: logoSize)

                            LaunchProgressPanel(
                                loadingText: loadingText,
                                progress: displayedProgress
                            )
                            .frame(maxWidth: panelWidth)
                            .offset(y: detailsPresented ? 0 : 8)
                            .opacity(detailsPresented ? 1 : 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, horizontalInset)
                .padding(.vertical, verticalInset)
            }
        }
        .accessibilityIdentifier("launch-experience")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(loadingText). \(mission)")
        .accessibilityValue("\(Int((displayedProgress * 100).rounded()))%")
        .onAppear {
            animationStart = Date()
            displayedProgress = progress
            if reduceMotion {
                sciencePresented = true
                detailsPresented = true
                return
            }

            withAnimation(.spring(response: 0.72, dampingFraction: 0.78).delay(0.04)) {
                sciencePresented = true
            }
            withAnimation(.easeOut(duration: 0.36).delay(0.12)) {
                detailsPresented = true
            }
        }
        .onChange(of: progress) { _, newProgress in
            let boundedProgress = min(max(newProgress, 0), 1)
            let nextProgress = max(displayedProgress, boundedProgress)
            if reduceMotion {
                displayedProgress = nextProgress
            } else {
                withAnimation(.smooth(duration: 0.32)) {
                    displayedProgress = nextProgress
                }
            }
        }
    }

    private func launchHero(fieldDiameter: CGFloat, logoSize: CGFloat) -> some View {
        // Keep only the decorative science field on the 60 fps timeline. The
        // real progress bar is a sibling, so timeline redraws can never restart
        // its one-way animation.
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion || !sciencePresented)) { timeline in
            let elapsed = sciencePresented && !reduceMotion
                ? max(0, timeline.date.timeIntervalSince(animationStart))
                : 0
            let pulse = sin(elapsed * .pi * 2 / 2.6)
            let logoScale = reduceMotion ? 1 : 1 + (pulse * 0.02)
            let logoLift = reduceMotion ? 0 : pulse * 3.2

            ZStack {
                LaunchScienceField(
                    isPresented: sciencePresented,
                    elapsed: elapsed,
                    reduceMotion: reduceMotion,
                    diameter: fieldDiameter
                )

                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: sciencePresented ? logoSize : Self.heroLogoSize,
                        height: sciencePresented ? logoSize : Self.heroLogoSize
                    )
                    .scaleEffect(logoScale)
                    .offset(y: logoLift)
                    .shadow(
                        color: Brand.deepOcean.opacity(sciencePresented ? 0.15 : 0),
                        radius: sciencePresented ? 10 : 0,
                        x: 0,
                        y: sciencePresented ? 7 : 0
                    )
                    .zIndex(2)
            }
            .frame(width: fieldDiameter, height: fieldDiameter)
        }
        .frame(width: fieldDiameter, height: fieldDiameter)
        .accessibilityHidden(true)
    }
}

private struct LaunchProgressPanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let loadingText: String
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    loadingLabel

                    progressValue
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    loadingLabel
                    progressValue
                }
            }

            LaunchScanTrack(progress: progress, accessibilityLabel: loadingText)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            Brand.paper.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Brand.navy.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: Brand.deepOcean.opacity(0.09), radius: 18, x: 0, y: 9)
    }

    private var loadingLabel: some View {
        Text(loadingText)
            .font(.headline)
            .foregroundStyle(Brand.navy)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.72 : 0.82)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressValue: some View {
        HStack(spacing: 5) {
            if progress >= 1 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Brand.moss)
                    .accessibilityHidden(true)
            }

            Text("\(Int((progress * 100).rounded()))%")
                .contentTransition(.numericText(value: progress))
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .foregroundStyle(Brand.lake)
        .accessibilityLabel("\(Int((progress * 100).rounded())) percent")
    }
}

private struct LaunchScienceField: View {
    let isPresented: Bool
    let elapsed: TimeInterval
    let reduceMotion: Bool
    let diameter: CGFloat

    var body: some View {
        let orbitRotation = reduceMotion ? 0 : elapsed * 7
        let primaryGearRotation = reduceMotion ? 0 : elapsed * 42
        let secondaryGearRotation = reduceMotion ? 0 : -elapsed * 64

        ZStack {
            Circle()
                .fill(Brand.paper.opacity(0.92))
                .frame(width: diameter * 0.76, height: diameter * 0.76)
                .shadow(color: Brand.deepOcean.opacity(0.08), radius: 18, x: 0, y: 9)

            Circle()
                .stroke(Brand.lake.opacity(0.17), lineWidth: 2)
                .frame(width: diameter * 0.90, height: diameter * 0.90)

            Circle()
                .trim(from: 0.04, to: 0.30)
                .stroke(Brand.lake.opacity(0.72), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: diameter * 0.96, height: diameter * 0.96)
                .rotationEffect(.degrees(orbitRotation))

            Circle()
                .trim(from: 0.48, to: 0.70)
                .stroke(Brand.coral.opacity(0.58), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: diameter * 0.84, height: diameter * 0.84)
                .rotationEffect(.degrees(-orbitRotation * 0.72))

            LaunchGear(color: Brand.coral, size: diameter * 0.18, rotation: primaryGearRotation)
                .offset(x: -diameter * 0.30, y: -diameter * 0.23)

            LaunchGear(color: Brand.lake, size: diameter * 0.115, rotation: secondaryGearRotation)
                .offset(x: -diameter * 0.20, y: -diameter * 0.34)

            Image(systemName: "atom")
                .font(.system(size: diameter * 0.14, weight: .medium))
                .foregroundStyle(Brand.lake)
                .offset(x: diameter * 0.32, y: -diameter * 0.25)

            Image(systemName: "testtube.2")
                .font(.system(size: diameter * 0.135, weight: .medium))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Brand.coral, Brand.sun)
                .rotationEffect(.degrees(-9))
                .offset(x: diameter * 0.31, y: diameter * 0.27)

            LaunchMoleculeMark()
                .frame(width: diameter * 0.18, height: diameter * 0.15)
                .offset(x: -diameter * 0.32, y: diameter * 0.28)

            Image(systemName: "sparkles")
                .font(.system(size: diameter * 0.07, weight: .semibold))
                .foregroundStyle(Brand.sun)
                .offset(x: diameter * 0.05, y: -diameter * 0.48)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(isPresented ? 1 : 0.56)
        .opacity(isPresented ? 1 : 0)
        .animation(
            reduceMotion ? nil : .spring(response: 0.72, dampingFraction: 0.78),
            value: isPresented
        )
        .drawingGroup(opaque: false, colorMode: .linear)
        .accessibilityHidden(true)
    }
}

private struct LaunchGear: View {
    let color: Color
    let size: CGFloat
    let rotation: Double

    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
            .shadow(color: color.opacity(0.14), radius: 4, x: 0, y: 2)
    }
}

private struct LaunchMoleculeMark: View {
    var body: some View {
        Canvas { context, size in
            let points = [
                CGPoint(x: size.width * 0.18, y: size.height * 0.68),
                CGPoint(x: size.width * 0.50, y: size.height * 0.28),
                CGPoint(x: size.width * 0.82, y: size.height * 0.64)
            ]

            var bonds = Path()
            bonds.move(to: points[0])
            bonds.addLine(to: points[1])
            bonds.addLine(to: points[2])
            context.stroke(
                bonds,
                with: .color(Brand.navy.opacity(0.72)),
                style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
            )

            let colors = [Brand.coral, Brand.lake, Brand.sun]
            for (index, point) in points.enumerated() {
                let radius: CGFloat = index == 1 ? 7 : 6
                let node = Path(
                    ellipseIn: CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                context.fill(node, with: .color(colors[index]))
                context.stroke(node, with: .color(Brand.paper), lineWidth: 2)
            }
        }
    }
}

private struct LaunchScanTrack: View {
    let progress: Double
    let accessibilityLabel: String

    var body: some View {
        GeometryReader { proxy in
            let boundedProgress = min(max(progress, 0), 1)
            let fillWidth = proxy.size.width * CGFloat(boundedProgress)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Brand.lake.opacity(0.14))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Brand.lake, Brand.electricBlue, Brand.sun],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: fillWidth)

                Capsule()
                    .strokeBorder(Brand.navy.opacity(0.08), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
        .accessibilityIdentifier("launch-progress")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue("\(Int((progress * 100).rounded()))%")
    }
}

private actor AppRefreshScheduleState {
    private var lastScheduledAt: Date?

    func claimSubmission(now: Date, minimumInterval: TimeInterval) -> Bool {
        if let lastScheduledAt,
           now.timeIntervalSince(lastScheduledAt) < minimumInterval {
            return false
        }

        lastScheduledAt = now
        return true
    }

    func clearSubmission(at date: Date) {
        if lastScheduledAt == date {
            lastScheduledAt = nil
        }
    }
}
