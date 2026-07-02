import SwiftUI
import CoreText

/// Registers the bundled brand fonts (Exo 2, JetBrains Mono — variable
/// TTFs) for this process. Called once from `AinkradApp.init`, before any
/// view renders.
enum FontRegistrar {
    static func registerBundledFonts() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// The two brand typefaces — see 06 Brand/Brand Identity.md. Exo 2 for
/// display/UI text, JetBrains Mono for data and HUD readouts. Falls back
/// to the system face automatically if registration failed.
enum AinkradFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Exo 2", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("JetBrains Mono", size: size).weight(weight)
    }
}
