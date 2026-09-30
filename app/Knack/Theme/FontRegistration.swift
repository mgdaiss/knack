import CoreText
import Foundation

enum FontRegistration {
    /// Registers the bundled Nunito faces for this process. Safe to call more than once.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
