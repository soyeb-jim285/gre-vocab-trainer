import SwiftUI

/// The whole visual vocabulary, in one place.
///
/// Dark, typographic, one accent. Liquid Glass is reserved for the navigation
/// layer -- Apple's guidance is that glass floats *above* content, never becomes
/// it, and glass sampling glass reads as mud.
enum Theme {

    // MARK: Colour

    static let ground = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let raised = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let hairline = Color.white.opacity(0.08)

    static let accent = Color(red: 0.85, green: 0.72, blue: 0.44)   // warm brass
    static let positive = Color(red: 0.44, green: 0.78, blue: 0.58)
    static let negative = Color(red: 0.89, green: 0.44, blue: 0.42)

    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.34)

    static func tint(forScore score: Int) -> Color {
        switch score {
        case 90...: positive
        case 70..<90: accent
        case 50..<70: Color(red: 0.90, green: 0.68, blue: 0.35)
        default: negative
        }
    }

    // MARK: Type

    /// The word under study, and nothing else, gets the serif.
    static func headword(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static let definition = Font.system(size: 19, weight: .regular, design: .serif)
    static let body = Font.system(size: 16, weight: .regular)
    static let label = Font.system(size: 12, weight: .medium).width(.expanded)
    static let mono = Font.system(size: 15, weight: .regular, design: .monospaced)

    // MARK: Metrics

    static let gutter: CGFloat = 24
    static let cardRadius: CGFloat = 22
}

extension View {
    /// A content surface. Solid on purpose -- see the note on Theme.
    func cardSurface() -> some View {
        padding(Theme.gutter)
            .background(Theme.raised, in: .rect(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }

    func screenBackground() -> some View {
        background(Theme.ground.ignoresSafeArea())
    }
}
