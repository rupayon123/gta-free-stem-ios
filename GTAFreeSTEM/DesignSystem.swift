import SwiftUI

enum Brand {
    static let ink = Color(red: 0.05, green: 0.07, blue: 0.08)
    static let cream = Color(red: 1.00, green: 0.97, blue: 0.87)
    static let paper = Color(red: 1.00, green: 0.99, blue: 0.93)
    static let sky = Color(red: 0.50, green: 0.78, blue: 0.86)
    static let lake = Color(red: 0.06, green: 0.44, blue: 0.52)
    static let navy = Color(red: 0.04, green: 0.18, blue: 0.33)
    static let deepOcean = Color(red: 0.02, green: 0.09, blue: 0.24)
    static let nightBlue = Color(red: 0.03, green: 0.18, blue: 0.36)
    static let electricBlue = Color(red: 0.10, green: 0.62, blue: 0.88)
    static let ice = Color(red: 0.90, green: 0.98, blue: 1.00)
    static let mintFoam = Color(red: 0.72, green: 0.94, blue: 0.88)
    static let moss = Color(red: 0.55, green: 0.76, blue: 0.48)
    static let sun = Color(red: 1.00, green: 0.73, blue: 0.12)
    static let coral = Color(red: 0.95, green: 0.34, blue: 0.22)
    static let orange = Color(red: 1.00, green: 0.49, blue: 0.19)
    static let lavender = Color(red: 0.60, green: 0.54, blue: 0.86)
    static let night = Color(red: 0.01, green: 0.04, blue: 0.16)
    static let nightCard = Color(red: 0.03, green: 0.14, blue: 0.29)
    static let chalk = ice

    static var blue: Color { lake }
    static var aqua: Color { sky }
    static var mint: Color { moss }

    static func pageGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    night,
                    deepOcean,
                    Color(red: 0.00, green: 0.28, blue: 0.48),
                    Color(red: 0.02, green: 0.42, blue: 0.56),
                    Color(red: 0.15, green: 0.18, blue: 0.48)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [mintFoam, Color(red: 0.98, green: 0.94, blue: 0.70), Color(red: 0.94, green: 0.73, blue: 0.62), Color(red: 0.79, green: 0.93, blue: 0.96)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nightCard.opacity(0.97) : paper
    }

    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nightBlue.opacity(0.96) : cream
    }

    static func outline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? ice.opacity(0.96) : ink
    }

    static func mutedText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.68, green: 0.90, blue: 1.00).opacity(0.86) : ink.opacity(0.66)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? electricBlue.opacity(0.78) : ink.opacity(0.88)
    }
}

struct StorybookBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Brand.pageGradient(for: colorScheme)
                .ignoresSafeArea()
            DoodlePattern()
                .stroke((colorScheme == .dark ? Brand.electricBlue : Brand.outline(for: colorScheme)).opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 2)
                .ignoresSafeArea()
        }
    }
}

private struct DoodlePattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 86

        for x in stride(from: rect.minX - step, through: rect.maxX + step, by: step) {
            for y in stride(from: rect.minY - step, through: rect.maxY + step, by: step) {
                let center = CGPoint(x: x + step * 0.5, y: y + step * 0.5)
                path.addEllipse(in: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6))
                path.move(to: CGPoint(x: center.x - 18, y: center.y + 24))
                path.addLine(to: CGPoint(x: center.x + 20, y: center.y + 12))
                path.move(to: CGPoint(x: center.x + 26, y: center.y - 18))
                path.addCurve(
                    to: CGPoint(x: center.x + 44, y: center.y - 8),
                    control1: CGPoint(x: center.x + 31, y: center.y - 31),
                    control2: CGPoint(x: center.x + 40, y: center.y - 28)
                )
            }
        }

        return path
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Brand.cardFill(for: colorScheme), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Brand.surfaceStroke(for: colorScheme), lineWidth: 2)
            }
            .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 8, x: 0, y: 3)
    }
}

struct StickerBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var color: Color = Brand.sun
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.black))
        .lineLimit(1)
        .minimumScaleFactor(0.78)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(colorScheme == .dark ? 0.82 : 0.72), in: Capsule())
        .overlay {
            Capsule().stroke(colorScheme == .dark ? Brand.deepOcean.opacity(0.92) : Brand.outline(for: colorScheme), lineWidth: 2)
        }
        .foregroundStyle(colorScheme == .dark ? Brand.ink : Brand.ink)
    }
}

struct BrandLogoImage: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false
    @State private var tapPulse = 0
    var size: CGFloat = 156

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.42 : 0.20), radius: 0, x: 4, y: 6)
            .scaleEffect(reduceMotion ? 1 : (isBobbing ? 1.018 : 0.992))
            .scaleEffect(reduceMotion ? 1 : (tapPulse % 2 == 0 ? 1 : 1.085))
            .rotationEffect(.degrees(reduceMotion ? 0 : (isBobbing ? 0.5 : -0.35)))
            .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: isBobbing)
            .animation(.spring(response: 0.22, dampingFraction: 0.48), value: tapPulse)
            .onAppear {
                guard !reduceMotion else { return }
                isBobbing = true
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !reduceMotion else { return }
                tapPulse += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    tapPulse += 1
                }
            }
            .accessibilityLabel(AppText.shared.string("brand", language: AppLanguage.normalized(UserDefaults.standard.string(forKey: "preferredLanguageCode") ?? AppLanguage.en.rawValue)))
    }
}

struct HuntActivityIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let phase: HuntPhase
    let isActive: Bool
    var size: CGFloat = 62
    @State private var isBreathing = false
    @State private var isOrbiting = false
    @State private var tapPulse = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(Brand.raisedFill(for: colorScheme))
                .overlay {
                    Circle().stroke(Brand.outline(for: colorScheme), lineWidth: max(size * 0.045, 2.5))
                }
                .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.30 : 0.16), radius: 0, x: size * 0.06, y: size * 0.08)

            Circle()
                .fill(colorScheme == .dark ? Brand.deepOcean.opacity(0.94) : Brand.ice)
                .frame(width: size * 0.68, height: size * 0.68)
                .overlay {
                    Circle().stroke(Brand.sky.opacity(colorScheme == .dark ? 0.95 : 0.72), lineWidth: max(size * 0.035, 2))
                }

            orbitDot(color: Brand.coral, radius: size * 0.34, dotSize: size * 0.12, offsetDegrees: 18)
            orbitDot(color: Brand.sun, radius: size * 0.31, dotSize: size * 0.10, offsetDegrees: 142)
            orbitDot(color: Brand.lake, radius: size * 0.27, dotSize: size * 0.085, offsetDegrees: 264)

            Image(systemName: phase.icon)
                .font(.system(size: size * 0.40, weight: .black))
                .symbolRenderingMode(.palette)
                .foregroundStyle(iconPrimaryColor, iconSecondaryColor)
                .scaleEffect(reduceMotion ? 1 : (isActive ? 1.04 : 1.0))
        }
        .frame(width: size, height: size)
        .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.025 : 0.985))
        .scaleEffect(reduceMotion ? 1 : (tapPulse % 2 == 0 ? 1 : 1.10))
        .rotationEffect(.degrees(reduceMotion ? 0 : (isBreathing ? 0.7 : -0.45)))
        .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: isBreathing)
        .animation(isActive && !reduceMotion ? .linear(duration: 1.05).repeatForever(autoreverses: false) : .spring(response: 0.42, dampingFraction: 0.72), value: isOrbiting)
        .animation(.spring(response: 0.22, dampingFraction: 0.48), value: tapPulse)
        .onAppear {
            guard !reduceMotion else { return }
            isBreathing = true
            isOrbiting = isActive
        }
        .onChange(of: isActive) { _, active in
            guard !reduceMotion else { return }
            isOrbiting = active
        }
        .contentShape(Circle())
        .onTapGesture {
            guard !reduceMotion else { return }
            tapPulse += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                tapPulse += 1
            }
        }
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

    private var iconSecondaryColor: Color {
        colorScheme == .dark ? Brand.chalk : Brand.ink
    }

    private func orbitDot(color: Color, radius: CGFloat, dotSize: CGFloat, offsetDegrees: Double) -> some View {
        Circle()
            .fill(color)
            .frame(width: dotSize, height: dotSize)
            .overlay {
                Circle().stroke(Brand.outline(for: colorScheme), lineWidth: max(dotSize * 0.18, 1.25))
            }
            .offset(x: radius)
            .rotationEffect(.degrees(reduceMotion ? offsetDegrees : (isOrbiting ? 360 + offsetDegrees : (isBreathing ? offsetDegrees + 8 : offsetDegrees - 4))))
    }
}

struct ThemeToolbarButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: SessionStore
    @State private var isBreathing = false
    var showLabel = true

    var body: some View {
        Button(action: toggleTheme) {
            HStack(spacing: 7) {
                Image(systemName: isDark ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 13, weight: .black))
                if showLabel {
                    Text(session.text("theme"))
                        .font(.caption.weight(.black))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, showLabel ? 12 : 0)
            .frame(width: showLabel ? nil : 38, height: showLabel ? 34 : 38)
            .background(fill, in: Capsule())
            .overlay {
                Capsule().stroke(stroke, lineWidth: 1.8)
            }
            .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.26 : 0.12), radius: 0, x: 2, y: 3)
                .scaleEffect(reduceMotion ? 1 : (isBreathing ? 1.035 : 0.98))
                .rotationEffect(.degrees(reduceMotion ? 0 : (isBreathing ? 1.2 : -0.8)))
                .animation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true), value: isBreathing)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(session.text("theme"))
        .onAppear {
            guard !reduceMotion else { return }
            isBreathing = true
        }
    }

    private var isDark: Bool {
        if session.preferredTheme == "Dark" { return true }
        if session.preferredTheme == "Light" { return false }
        return colorScheme == .dark
    }

    private var fill: Color {
        isDark ? Brand.sun : Brand.deepOcean.opacity(colorScheme == .dark ? 0.96 : 0.92)
    }

    private var foreground: Color {
        isDark ? Brand.deepOcean : Brand.ice
    }

    private var stroke: Color {
        colorScheme == .dark ? Brand.electricBlue.opacity(0.95) : Brand.ink
    }

    private func toggleTheme() {
        session.preferredTheme = isDark ? "Light" : "Dark"
    }
}

struct StoryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    enum Kind {
        case primary
        case secondary
        case quiet
    }

    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.black))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(foreground)
            .background(background.opacity(configuration.isPressed ? 0.78 : 1), in: Capsule())
            .overlay {
                Capsule().stroke(Brand.surfaceStroke(for: colorScheme), lineWidth: 2)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -1.4 : 0))
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: Brand.coral
        case .secondary: Brand.sun
        case .quiet: colorScheme == .dark ? Brand.navy.opacity(0.92) : Brand.raisedFill(for: colorScheme)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary, .quiet: Brand.outline(for: colorScheme)
        }
    }
}

struct StoryFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.body.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Brand.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Brand.surfaceStroke(for: colorScheme), lineWidth: 2)
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct StoryPickerRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.headline.weight(.bold))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Brand.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Brand.surfaceStroke(for: colorScheme), lineWidth: 2)
            }
            .foregroundStyle(Brand.outline(for: colorScheme))
    }
}

struct StorySectionTitle: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var systemImage: String = "sparkle.magnifyingglass"

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Brand.coral)
            Text(text)
                .font(.title3.weight(.black))
            Spacer()
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
            HStack(spacing: 8) {
                content
            }

            VStack(alignment: .leading, spacing: 8) {
                content
            }
        }
    }
}

extension View {
    func cardSurface(padding: CGFloat = 16, cornerRadius: CGFloat = 28) -> some View {
        modifier(CardSurface(padding: padding, cornerRadius: cornerRadius))
    }

    func storyField() -> some View {
        modifier(StoryFieldModifier())
    }

    func storyPickerRow() -> some View {
        modifier(StoryPickerRowModifier())
    }
}
