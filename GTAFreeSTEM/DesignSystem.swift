import SwiftUI

/// The app's single visual source of truth.
///
/// The logo carries the playful STEM character. Interface chrome stays calm,
/// legible, and native so the opportunities remain the most prominent content.
enum Brand {
    // MARK: Core brand colours

    static let ink = Color(red: 0.05, green: 0.09, blue: 0.11)
    static let cream = Color(red: 0.98, green: 0.97, blue: 0.92)
    static let paper = Color(red: 0.99, green: 0.99, blue: 0.97)
    static let sky = Color(red: 0.45, green: 0.75, blue: 0.80)
    static let lake = Color(red: 0.05, green: 0.40, blue: 0.45)
    static let navy = Color(red: 0.04, green: 0.18, blue: 0.28)
    static let deepOcean = Color(red: 0.03, green: 0.10, blue: 0.14)
    static let nightBlue = Color(red: 0.06, green: 0.16, blue: 0.20)
    static let electricBlue = Color(red: 0.31, green: 0.78, blue: 0.77)
    static let ice = Color(red: 0.94, green: 0.98, blue: 0.97)
    static let mintFoam = Color(red: 0.84, green: 0.94, blue: 0.90)
    static let moss = Color(red: 0.39, green: 0.65, blue: 0.43)
    static let sun = Color(red: 0.96, green: 0.70, blue: 0.22)
    static let coral = Color(red: 0.82, green: 0.28, blue: 0.20)
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
            : Color(red: 0.965, green: 0.973, blue: 0.955)
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
        ZStack {
            Brand.pageGradient(for: colorScheme)
                .ignoresSafeArea()

            // One quiet discovery field carries the brand across screens without
            // competing with text, cards, maps, or native navigation controls.
            Circle()
                .fill(Brand.sky.opacity(colorScheme == .dark ? 0.07 : 0.10))
                .frame(width: 340, height: 340)
                .blur(radius: 28)
                .offset(x: 180, y: -320)

            Circle()
                .fill(Brand.sun.opacity(colorScheme == .dark ? 0.035 : 0.07))
                .frame(width: 280, height: 280)
                .blur(radius: 32)
                .offset(x: -190, y: 380)
        }
        .accessibilityHidden(true)
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var padding: CGFloat = AppSpacing.standard
    var cornerRadius: CGFloat = AppRadius.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                reduceTransparency
                    ? Brand.cardFill(for: colorScheme)
                    : Brand.cardFill(for: colorScheme).opacity(0.97),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Brand.surfaceStroke(for: colorScheme), lineWidth: 0.75)
            }
            .shadow(
                color: Brand.deepOcean.opacity(colorScheme == .dark ? 0.18 : 0.07),
                radius: colorScheme == .dark ? 10 : 14,
                x: 0,
                y: colorScheme == .dark ? 5 : 7
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
        .lineLimit(1)
        .minimumScaleFactor(0.82)
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
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
