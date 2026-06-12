import SwiftUI

enum Brand {
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.10)
    static let cream = Color(red: 1.00, green: 0.96, blue: 0.86)
    static let paper = Color(red: 1.00, green: 0.99, blue: 0.93)
    static let sky = Color(red: 0.47, green: 0.75, blue: 0.86)
    static let lake = Color(red: 0.11, green: 0.43, blue: 0.55)
    static let moss = Color(red: 0.61, green: 0.72, blue: 0.41)
    static let sun = Color(red: 1.00, green: 0.74, blue: 0.38)
    static let coral = Color(red: 0.92, green: 0.39, blue: 0.31)
    static let lavender = Color(red: 0.60, green: 0.56, blue: 0.78)
    static let night = Color(red: 0.06, green: 0.13, blue: 0.13)
    static let nightCard = Color(red: 0.14, green: 0.17, blue: 0.15)
    static let chalk = Color(red: 0.95, green: 0.93, blue: 0.84)

    static var blue: Color { lake }
    static var aqua: Color { sky }
    static var mint: Color { moss }

    static func pageGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [night, Color(red: 0.12, green: 0.18, blue: 0.12), Color(red: 0.10, green: 0.12, blue: 0.19)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        return LinearGradient(
            colors: [Color(red: 0.84, green: 0.95, blue: 0.96), Color(red: 1.00, green: 0.94, blue: 0.74), Color(red: 0.96, green: 0.78, blue: 0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func cardFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? nightCard : paper
    }

    static func raisedFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.19, green: 0.21, blue: 0.18) : cream
    }

    static func outline(for scheme: ColorScheme) -> Color {
        scheme == .dark ? chalk.opacity(0.92) : ink
    }

    static func mutedText(for scheme: ColorScheme) -> Color {
        scheme == .dark ? chalk.opacity(0.72) : ink.opacity(0.64)
    }
}

struct StorybookBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Brand.pageGradient(for: colorScheme)
                .ignoresSafeArea()
            DoodlePattern()
                .stroke(Brand.outline(for: colorScheme).opacity(colorScheme == .dark ? 0.08 : 0.10), lineWidth: 2)
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
                    .stroke(Brand.outline(for: colorScheme), lineWidth: 2.75)
            }
            .overlay(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Brand.sun.opacity(colorScheme == .dark ? 0.36 : 0.62), lineWidth: 3)
                    .offset(x: 4, y: 5)
                    .mask(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
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
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(colorScheme == .dark ? 0.82 : 0.72), in: Capsule())
        .overlay {
            Capsule().stroke(Brand.outline(for: colorScheme), lineWidth: 2)
        }
        .foregroundStyle(colorScheme == .dark ? Brand.ink : Brand.ink)
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
            .padding(size * 0.04)
            .background(
                Circle()
                    .fill(Brand.raisedFill(for: colorScheme).opacity(colorScheme == .dark ? 0.42 : 0.58))
            )
            .shadow(color: Brand.ink.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 0, x: 5, y: 7)
            .accessibilityLabel("GTA FREE STEM Opportunities")
    }
}

struct StorybookWordmark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            BrandLogoImage(size: 156)

            Text("GTA FREE STEM")
                .font(.system(size: 28, weight: .black, design: .rounded))
                .kerning(0.5)

            Text("Opportunities")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Brand.sun, in: Capsule())
                .overlay {
                    Capsule().stroke(Brand.outline(for: colorScheme), lineWidth: 2)
                }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Brand.outline(for: colorScheme))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Brand.raisedFill(for: colorScheme), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Brand.outline(for: colorScheme), lineWidth: 3)
        }
        .rotationEffect(.degrees(-1))
        .accessibilityLabel("GTA FREE STEM Opportunities")
    }
}

struct DoodleSpark: View {
    let color: Color
    let rotation: Double

    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: 28, weight: .black))
            .foregroundStyle(color)
            .rotationEffect(.degrees(rotation))
            .accessibilityHidden(true)
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
                Capsule().stroke(Brand.outline(for: colorScheme), lineWidth: 2.25)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .rotationEffect(.degrees(configuration.isPressed ? -1.4 : 0))
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
    }

    private var background: Color {
        switch kind {
        case .primary: Brand.coral
        case .secondary: Brand.sun
        case .quiet: Brand.raisedFill(for: colorScheme)
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
                    .stroke(Brand.outline(for: colorScheme), lineWidth: 2)
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
                    .stroke(Brand.outline(for: colorScheme), lineWidth: 2)
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
