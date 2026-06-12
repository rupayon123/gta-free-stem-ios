import SwiftUI

enum Brand {
    static let blue = Color(red: 0.09, green: 0.46, blue: 0.78)
    static let aqua = Color(red: 0.22, green: 0.78, blue: 0.85)
    static let mint = Color(red: 0.44, green: 0.85, blue: 0.67)
    static let sun = Color(red: 1.0, green: 0.82, blue: 0.4)
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.48)
}

struct CardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.22), lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface() -> some View {
        modifier(CardSurface())
    }
}
