import SwiftUI
import UIKit

/// The whole visual vocabulary, in one place.
///
/// Typographic, one accent, and honest in both appearances. Liquid Glass is
/// reserved for the navigation layer -- Apple's guidance is that glass floats
/// *above* content, never becomes it, and glass sampling glass reads as mud.
///
/// Surfaces and text come from the system's semantic colours rather than being
/// spelled out, so they follow the appearance, the contrast setting and any
/// future system change for free. Only the four brand colours are stated, and
/// each states both halves: a colour defined once, for dark, is invisible in
/// light. Every light value below clears 4.5:1 against the light background.
enum Theme {

    // MARK: Colour

    static let ground = Color(.systemBackground)
    static let raised = Color(.secondarySystemBackground)
    static let hairline = Color(.separator)

    /// Warm brass. The light twin is a much darker bronze: the dark value is
    /// barely legible on white.
    static let accent = Color(light: Color(red: 0.52, green: 0.38, blue: 0.12),
                              dark: Color(red: 0.85, green: 0.72, blue: 0.44))
    static let positive = Color(light: Color(red: 0.13, green: 0.48, blue: 0.28),
                                dark: Color(red: 0.44, green: 0.78, blue: 0.58))
    static let negative = Color(light: Color(red: 0.70, green: 0.13, blue: 0.11),
                                dark: Color(red: 0.89, green: 0.44, blue: 0.42))
    /// Not-wrong-but-not-right. A real token because it was previously an inline
    /// literal repeated in two unrelated files.
    static let caution = Color(light: Color(red: 0.60, green: 0.40, blue: 0.05),
                               dark: Color(red: 0.90, green: 0.68, blue: 0.35))

    static let primaryText = Color.primary
    static let secondaryText = Color.secondary
    static let tertiaryText = Color(.tertiaryLabel)

    /// These are drawn as text on a raised surface, so every band has to carry
    /// text contrast rather than merely being distinguishable.
    static func tint(forScore score: Int) -> Color {
        switch score {
        case 90...: positive
        case 70..<90: accent
        case 50..<70: caution
        default: negative
        }
    }

    // MARK: Type

    /// The word under study, and nothing else, gets the serif.
    ///
    /// Takes a text style rather than a point size so it grows with the reader's
    /// setting. The hero word tops out at `.largeTitle`, which starts smaller
    /// than the fixed 44pt it replaces but, unlike it, keeps going at the
    /// accessibility sizes.
    static func headword(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif)
    }

    static let definition = Font.system(.body, design: .serif)
    static let body = Font.body
    static let label = Font.system(.caption).weight(.medium).width(.expanded)
    static let mono = Font.system(.callout, design: .monospaced)

    // MARK: Metrics

    static let gutter: CGFloat = 24
    static let cardRadius: CGFloat = 22
}

extension Color {
    /// One colour with both appearances stated. Reading `colorScheme` instead
    /// would not work here: these are static constants, with no view to read an
    /// environment from.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
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
