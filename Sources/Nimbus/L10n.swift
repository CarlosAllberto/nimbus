import Foundation

extension Bundle {
    /// Where `Localizable.xcstrings` lives: the SwiftPM resource bundle for
    /// `swift build` (a bare executable has no `.app`), the app bundle for
    /// the Xcode build. Pass it as `bundle:` to every localized lookup.
    static var l10n: Bundle {
        #if SWIFT_PACKAGE
        // A bare executable ignores the system language for resource bundles,
        // so pick the matching `.lproj` by hand.
        packageLocalized
        #else
        Bundle.main
        #endif
    }
}

#if SWIFT_PACKAGE
private let packageLocalized: Bundle = {
    let language = Bundle.preferredLocalizations(from: Bundle.module.localizations, forPreferences: Locale.preferredLanguages).first ?? "en"
    return Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.module
}()
#endif

/// One line per representative key, resolved through `bundle` (default
/// `Bundle.l10n`, i.e. the system language). A bare `swift build` executable
/// ignores the system language for resource bundles, so a scratch harness can
/// pass `Bundle(path: <bundle>/Contents/Resources/pt-BR.lproj)` to force one.
/// Not wired into the app.
func l10nSelfCheck(bundle: Bundle = .l10n) -> [String] {
    [
        String(localized: "Compress Images", bundle: bundle),
        String(localized: "Low compression", bundle: bundle),
        String(localized: "\(1) files", bundle: bundle),
        String(localized: "\(3) files", bundle: bundle),
        String(localized: "\(12)% smaller", bundle: bundle),
        String(localized: "Update Available (\("1.2"))", bundle: bundle),
        String(localized: "This \("image") is larger than the \(250) MB limit.", bundle: bundle),
        String(localized: "Version \("1.0") (build \("7"))", bundle: bundle),
        String(localized: "\("X"), accepts \("image") files", bundle: bundle),
    ]
}
