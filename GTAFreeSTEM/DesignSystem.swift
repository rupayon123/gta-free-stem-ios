import SwiftUI
import UIKit
#if DEBUG
import SwiftData
#endif

/// The app's single visual source of truth.
///
/// The logo carries the playful STEM character. Interface chrome stays calm,
/// legible, and native so the opportunities remain the most prominent content.
enum Brand {
    /// A compact, language-neutral brand mark for constrained navigation chrome.
    /// Product headlines continue to use the localized full name.
    static let compactName = "GTA FREE STEM"

    // MARK: Core brand colours

    static let ink = Color(red: 16/255, green: 52/255, blue: 82/255)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.92)
    static let paper = Color(red: 0.99, green: 0.99, blue: 0.97)
    static let sky = Color(red: 0.45, green: 0.75, blue: 0.80)
    static let lake = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.31, green: 0.78, blue: 0.77, alpha: 1)
            : UIColor(red: 8/255, green: 119/255, blue: 124/255, alpha: 1)
    })
    static let navy = Color(red: 16/255, green: 52/255, blue: 82/255)
    static let deepOcean = Color(red: 0.03, green: 0.10, blue: 0.14)
    static let nightBlue = Color(red: 0.06, green: 0.16, blue: 0.20)
    static let electricBlue = Color(red: 0.31, green: 0.78, blue: 0.77)
    static let ice = Color(red: 0.94, green: 0.98, blue: 0.97)
    static let mintFoam = Color(red: 0.84, green: 0.94, blue: 0.90)
    static let moss = Color(red: 0.39, green: 0.65, blue: 0.43)
    static let sun = Color(red: 244/255, green: 196/255, blue: 49/255)
    static let coral = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.706, blue: 0.671, alpha: 1)
            : UIColor(red: 183/255, green: 55/255, blue: 44/255, alpha: 1)
    })
    static let orange = Color(red: 0.91, green: 0.48, blue: 0.20)
    static let lavender = Color(red: 0.55, green: 0.50, blue: 0.78)
    static let night = Color(red: 0.025, green: 0.065, blue: 0.085)
    static let nightCard = Color(red: 0.055, green: 0.13, blue: 0.16)
    static let chalk = ice

    static var blue: Color { lake }
    static var aqua: Color { sky }
    static var mint: Color { moss }

    // MARK: Semantic colours

    static func canvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? night
            : cream
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? nightCard
            : Color(red: 0.995, green: 0.995, blue: 0.985)
    }

    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.18, blue: 0.21)
            : Color(red: 0.925, green: 0.95, blue: 0.93)
    }

    static func outline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? ice : navy
    }

    static func mutedText(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.68, green: 0.77, blue: 0.78)
            : Color(red: 0.29, green: 0.38, blue: 0.39)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.14)
            : navy.opacity(0.12)
    }

    static func actionFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? electricBlue : lake
    }

    static func actionForeground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? deepOcean : .white
    }

    static func selectionFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? electricBlue.opacity(0.18) : lake.opacity(0.10)
    }

    static func pageGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    night,
                    Color(red: 0.035, green: 0.12, blue: 0.15),
                    Color(red: 0.045, green: 0.10, blue: 0.13)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [
                Color(red: 0.935, green: 0.975, blue: 0.955),
                Color(red: 0.985, green: 0.975, blue: 0.925),
                Color(red: 0.965, green: 0.973, blue: 0.955)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum AppSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let standard: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 32
}

enum AppRadius {
    static let control: CGFloat = 14
    static let card: CGFloat = 20
    static let feature: CGFloat = 24
}

enum AppIconSize {
    static let small: CGFloat = 14
    static let standard: CGFloat = 18
    static let large: CGFloat = 24
}

struct StorybookBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Brand.canvas(for: colorScheme)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = AppSpacing.standard
    var cornerRadius: CGFloat = AppRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                Brand.cardFill(for: colorScheme),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

struct StickerBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var color: Color = Brand.sun
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            color.opacity(colorScheme == .dark ? 0.22 : 0.13),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(color.opacity(colorScheme == .dark ? 0.42 : 0.28), lineWidth: 0.75)
        }
        .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct BrandLogoImage: View {
    @Environment(\.colorScheme) private var colorScheme
    var size: CGFloat = 156

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(
                color: Brand.deepOcean.opacity(colorScheme == .dark ? 0.26 : 0.12),
                radius: 8,
                x: 0,
                y: 5
            )
            .accessibilityLabel(AppText.shared.string("brand", language: AppLanguage.preferred()))
    }
}

struct HuntActivityIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: HuntPhase
    let isActive: Bool
    var size: CGFloat = 62
    @State private var isOrbiting = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.raisedFill(for: colorScheme))
                .overlay {
                    Circle()
                        .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
                }

            Circle()
                .fill(iconPrimaryColor.opacity(colorScheme == .dark ? 0.19 : 0.11))
                .frame(width: size * 0.68, height: size * 0.68)

            Image(systemName: phase.icon)
                .font(.system(size: size * 0.36, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconPrimaryColor)

            if isActive {
                Circle()
                    .trim(from: 0.06, to: 0.26)
                    .stroke(
                        Brand.sun,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: size - 3, height: size - 3)
                    .rotationEffect(.degrees(isOrbiting ? 360 : 0))
            }
        }
        .frame(width: size, height: size)
        .onAppear { updateMotion() }
        .onChange(of: isActive) { _, _ in updateMotion() }
        .accessibilityHidden(true)
    }

    private var iconPrimaryColor: Color {
        switch phase {
        case .fresh:
            Brand.moss
        case .cached, .offline:
            Brand.lake
        default:
            Brand.coral
        }
    }

    private func updateMotion() {
        guard isActive, !reduceMotion else {
            isOrbiting = false
            return
        }
        isOrbiting = false
        withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
            isOrbiting = true
        }
    }
}

struct ThemeToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var session: SessionStore
    var showLabel = true

    var body: some View {
        Button(action: toggleTheme) {
            HStack(spacing: 7) {
                Image(systemName: isDark ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: AppIconSize.small, weight: .semibold))
                    .accessibilityHidden(true)
                if showLabel {
                    Text(session.text("theme"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
            .padding(.horizontal, showLabel ? 13 : 0)
            .frame(minWidth: 44, minHeight: 44)
            .background(Brand.raisedFill(for: colorScheme), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.text("theme"))
        .accessibilityValue(isDark ? session.text("dark") : session.text("light"))
    }

    private var isDark: Bool {
        if session.preferredTheme == "Dark" { return true }
        if session.preferredTheme == "Light" { return false }
        return colorScheme == .dark
    }

    private func toggleTheme() {
        session.preferredTheme = isDark ? "Light" : "Dark"
    }
}

struct StoryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Kind {
        case primary
        case secondary
        case quiet
        case destructive
    }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .foregroundStyle(foreground)
            .background(
                background.opacity(configuration.isPressed ? 0.84 : 1),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(border, lineWidth: kind == .primary ? 0 : 0.75)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary:
            Brand.actionFill(for: colorScheme)
        case .secondary:
            Brand.selectionFill(for: colorScheme)
        case .quiet:
            Brand.raisedFill(for: colorScheme)
        case .destructive:
            Color(red: 0.72, green: 0.12, blue: 0.14)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary:
            Brand.actionForeground(for: colorScheme)
        case .destructive:
            .white
        case .secondary, .quiet:
            Brand.outline(for: colorScheme)
        }
    }

    private var border: Color {
        switch kind {
        case .primary, .destructive:
            .clear
        case .secondary:
            Brand.lake.opacity(colorScheme == .dark ? 0.42 : 0.24)
        case .quiet:
            Brand.surfaceStroke(for: colorScheme)
        }
    }
}

struct SelectionChipStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(isSelected ? .semibold : .medium))
            .foregroundStyle(
                isSelected
                    ? Brand.actionFill(for: colorScheme)
                    : Brand.outline(for: colorScheme)
            )
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                isSelected
                    ? Brand.selectionFill(for: colorScheme)
                    : Brand.raisedFill(for: colorScheme),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? Brand.actionFill(for: colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.30)
                            : Brand.surfaceStroke(for: colorScheme),
                        lineWidth: 0.75
                    )
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

/// Places compact controls on complete rows instead of clipping the next item at
/// a narrow screen edge. The source order remains the VoiceOver reading order.
struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    var layoutDirection: LayoutDirection = .leftToRight

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = makeRows(proposal: proposal, subviews: subviews)
        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight = rows.reduce(0) { $0 + $1.height }
            + verticalSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? contentWidth, height: contentHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        var y = bounds.minY

        for row in rows {
            var x = layoutDirection == .rightToLeft ? bounds.maxX : bounds.minX
            for item in row.items {
                if layoutDirection == .rightToLeft {
                    x -= item.size.width
                }

                subviews[item.index].place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size)
                )

                if layoutDirection == .rightToLeft {
                    x -= horizontalSpacing
                } else {
                    x += item.size.width + horizontalSpacing
                }
            }
            y += row.height + verticalSpacing
        }
    }

    private func makeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let proposedWidth = proposal.width ?? .infinity
        var rows = [Row]()
        var row = Row()

        for index in subviews.indices {
            let idealSize = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = proposedWidth.isFinite ? min(idealSize.width, proposedWidth) : idealSize.width
            let itemSize = subviews[index].sizeThatFits(
                ProposedViewSize(width: itemWidth, height: nil)
            )
            let nextWidth = row.items.isEmpty
                ? itemSize.width
                : row.width + horizontalSpacing + itemSize.width

            if !row.items.isEmpty, nextWidth > proposedWidth {
                rows.append(row)
                row = Row()
            }
            row.append(index: index, size: itemSize, spacing: horizontalSpacing)
        }

        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }

    private struct Row {
        var items = [Item]()
        var width: CGFloat = 0
        var height: CGFloat = 0

        mutating func append(index: Int, size: CGSize, spacing: CGFloat) {
            if !items.isEmpty {
                width += spacing
            }
            items.append(Item(index: index, size: size))
            width += size.width
            height = max(height, size.height)
        }
    }

    private struct Item {
        let index: Int
        let size: CGSize
    }
}

struct StoryFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                Brand.raisedFill(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct StoryPickerRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.medium))
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .background(
                Brand.raisedFill(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct StorySectionTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var systemImage: String = "sparkle.magnifyingglass"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: AppIconSize.standard, weight: .semibold))
                .foregroundStyle(Brand.lake)
                .accessibilityHidden(true)
            Text(text)
                .font(.title3.weight(.semibold))
            Spacer(minLength: 8)
        }
        .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct FlowLabels<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) {
                content
            }

            VStack(alignment: .leading, spacing: 7) {
                content
            }
        }
    }
}

extension View {
    func cardSurface(
        padding: CGFloat = AppSpacing.standard,
        cornerRadius: CGFloat = AppRadius.card
    ) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius))
    }

    func storyField() -> some View {
        modifier(StoryFieldModifier())
    }

    func storyPickerRow() -> some View {
        modifier(StoryPickerRowModifier())
    }
}

/// Native discovery illustration informed by Hairline's isometric loupe.
/// Reference: lucasmarkes/hairline @ 37d2e78 (MIT, Lucas Marques).
/// Original GTA geometry; no DOM, pointer listener, timer, or idle animation.
struct DiscoveryLoupeScene: View, Animatable {
    @Environment(\.colorScheme) private var colorScheme
    nonisolated var progress: CGFloat = 0
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            var drawing = context
            let scale = min(size.width / 260, size.height / 160)
            drawing.translateBy(x: (size.width - 260 * scale) / 2, y: (size.height - 160 * scale) / 2)
            drawing.scaleBy(x: scale, y: scale)
            let ink = Brand.outline(for: colorScheme)
            let paper = Brand.cardFill(for: colorScheme)
            let stroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            func path(_ points: [CGPoint], close: Bool = false) -> Path {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for point in points.dropFirst() { p.addLine(to: point) }
                    if close { p.closeSubpath() }
                }
            }
            let sheet = path([CGPoint(x: 20, y: 91), CGPoint(x: 150, y: 46), CGPoint(x: 241, y: 91), CGPoint(x: 110, y: 143)], close: true)
            drawing.fill(sheet, with: .color(Brand.raisedFill(for: colorScheme)))
            drawing.stroke(sheet, with: .color(ink), style: stroke)
            for row in 0..<5 {
                let y = CGFloat(row) * 9
                drawing.stroke(path([CGPoint(x: 48 + y, y: 87 + y * 0.48), CGPoint(x: 151 + y, y: 52 + y * 0.48)]), with: .color(Brand.lake), style: StrokeStyle(lineWidth: 1))
            }
            // Toronto's tower and a few blocks form a place, rather than a generic spinner.
            let skyline = path([CGPoint(x: 156, y: 87), CGPoint(x: 156, y: 67), CGPoint(x: 168, y: 67), CGPoint(x: 168, y: 83), CGPoint(x: 179, y: 79), CGPoint(x: 179, y: 57), CGPoint(x: 192, y: 57), CGPoint(x: 192, y: 74), CGPoint(x: 205, y: 69)])
            drawing.stroke(skyline, with: .color(ink), style: stroke)
            drawing.stroke(path([CGPoint(x: 139, y: 87), CGPoint(x: 139, y: 25)]), with: .color(ink), style: stroke)
            drawing.fill(Path(ellipseIn: CGRect(x: 130, y: 43, width: 18, height: 7)), with: .color(Brand.sun))
            drawing.stroke(Path(ellipseIn: CGRect(x: 130, y: 43, width: 18, height: 7)), with: .color(ink), style: stroke)
            let x = 85 + min(1, max(0, progress)) * 50
            let y: CGFloat = 81
            // Three feet, a solid rim, and a bounded lens: all remain inside this scene.
            for foot in [CGPoint(x: -31, y: 22), CGPoint(x: 29, y: 23), CGPoint(x: 20, y: -9)] {
                drawing.stroke(path([CGPoint(x: x + foot.x, y: y + foot.y), CGPoint(x: x + foot.x * 0.7, y: y - 20 + foot.y * 0.35)]), with: .color(ink), style: stroke)
            }
            let lens = Path(ellipseIn: CGRect(x: x - 32, y: y - 43, width: 64, height: 39))
            drawing.fill(lens, with: .color(paper))
            var magnified = drawing
            magnified.clip(to: lens)
            for row in 0..<5 {
                magnified.stroke(path([CGPoint(x: x - 33, y: y - 22 + CGFloat(row) * 9), CGPoint(x: x + 35, y: y - 43 + CGFloat(row) * 9)]), with: .color(ink), style: StrokeStyle(lineWidth: 1.5))
            }
            drawing.stroke(lens, with: .color(Brand.lake), style: StrokeStyle(lineWidth: 4))
            drawing.fill(Path(ellipseIn: CGRect(x: 213, y: 33, width: 14, height: 14)), with: .color(Brand.sun))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 144)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Press feedback transforms only the drawing; layout and touch bounds stay fixed.
struct SpringPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

#if DEBUG
/// CI-only layout review of real screens with clearly labelled, app-owned samples.
/// The separate model container and defaults never replace personal saved data.
struct FrontendLayoutReview: View {
    @StateObject private var session: SessionStore
    @StateObject private var store: OpportunityStore
    @State private var ready = false
    @State private var container: ModelContainer
    private let screen = Self.option("-review-screen") ?? "home"
    private let isDark = ProcessInfo.processInfo.arguments.contains("-review-dark")
    private let largeText = ProcessInfo.processInfo.arguments.contains("-review-large-text")

    init() {
        let defaults = UserDefaults(suiteName: "GTAFreeSTEM.LayoutReview.\(UUID().uuidString)")!
        let reviewSession = SessionStore(defaults: defaults, preferredLanguages: [Self.option("-review-language") ?? "en"])
        reviewSession.preferredTheme = ProcessInfo.processInfo.arguments.contains("-review-dark") ? "Dark" : "Light"
        _session = StateObject(wrappedValue: reviewSession)
        _store = StateObject(wrappedValue: OpportunityStore(api: APIClient(), defaults: defaults))
        let schema = Schema([OpportunityCacheRecord.self, SavedHuntRecord.self, SeenOpportunityRecord.self, SavedOpportunityRecord.self])
        do {
            _container = State(initialValue: try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        } catch {
            preconditionFailure("Unable to create the isolated layout-review store: \(error)")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(session.text("layoutReviewBanner"))
                .font(.caption.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(8)
                .foregroundStyle(Brand.navy)
                .background(Brand.sun)
            reviewContent
        }
        .environmentObject(session)
        .environmentObject(store)
        .modelContainer(container)
        .environment(\.appStorageAccess, .persistent)
        .environment(\.locale, Locale(identifier: session.language.localeIdentifier))
        .environment(\.layoutDirection, session.language.layoutDirection)
        .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
        .preferredColorScheme(isDark ? .dark : .light)
        .task {
            guard !ready else { return }
            let prepared = await store.prepareScreenshotSnapshot()
            guard prepared else { return }
            if screen == "saved" {
                // The query and fixture must share the retained main context.
                // A temporary context resets its registered models on deinit.
                let context = container.mainContext
                do {
                    for opportunity in store.opportunities.prefix(3) {
                        context.insert(try SavedOpportunityRecord(opportunity: opportunity))
                    }
                    try context.save()
                    guard try context.fetchCount(FetchDescriptor<SavedOpportunityRecord>()) == 3 else {
                        preconditionFailure("The saved-layout fixture did not contain all three app-owned samples.")
                    }
                } catch {
                    preconditionFailure("Unable to seed the isolated saved-layout fixture: \(error)")
                }
            }
            ready = true
            // This marker proves fixture preparation only; the capture script waits for drawing.
            AppLaunchConfiguration.markScreenshotReady(true)
        }
    }

    private var reviewContent: some View {
        Group {
            if ready {
                if screen == "calendar", let sample = store.opportunities.first {
                    NavigationStack { OpportunityDetailView(opportunity: sample) }
                } else {
                    ContentView()
                }
            } else {
                ProgressView("Preparing app-owned layout samples")
            }
        }
    }

    private static func option(_ flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
