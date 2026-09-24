import Foundation

enum FormSlice {
    case sliceA
    case sliceB
}

enum FormToolKind: String, CaseIterable {
    // Slice A
    case whoisScan = "whois-scan"
    case dnsCheck = "dns-check"
    case siteSpeed = "site-speed"
    case wordpressInspector = "wordpress-inspector"
    case policyGenerator = "policy-generator"
    case contractPDF = "contract-pdf"
    case qrCode = "qrcode"

    // Slice B
    case copyGenerator = "copy-generator"
    case jsonCreator = "json-creator"
    case responsiveFontClamp = "responsive-font-clamp"
    case htmlMinify = "html-minify"
    case jsMinify = "js-minify"
    case passwordGenerator = "password-generator"
    case colorConvert = "color-convert"
    case contrastCheck = "contrast-check"
    case waLink = "wa-link"

    var slice: FormSlice {
        switch self {
        case .whoisScan, .dnsCheck, .siteSpeed, .wordpressInspector,
             .policyGenerator, .contractPDF, .qrCode:
            .sliceA
        case .copyGenerator, .jsonCreator, .responsiveFontClamp, .htmlMinify,
             .jsMinify, .passwordGenerator, .colorConvert, .contrastCheck, .waLink:
            .sliceB
        }
    }

    /// The two minify tools share a shape no other form has: a single code
    /// editor plus a minify/unminify choice. The choice belongs beside the
    /// action button, where every file tool already keeps its options, and the
    /// editor gets the height the pane can spare instead of a fixed 220pt box
    /// inside a scroll view.
    var isMinifyTool: Bool { self == .htmlMinify || self == .jsMinify }

    /// Forms built around one text editor lay out without a scroll view, so
    /// the editor takes the height the pane can spare. Copy Generator's Pages
    /// step is a growing list, so it keeps scrolling.
    func fillsHeight(atStep step: Int) -> Bool {
        switch self {
        case .htmlMinify, .jsMinify, .waLink, .qrCode: true
        case .copyGenerator: step != 1
        default: false
        }
    }

    /// Titles of the steps a long form is broken into, or nil for the forms
    /// short enough to stay on one page. Declared here, beside the rest of
    /// what varies per tool, so the slices only have to answer "render step
    /// N" — they never decide how many there are.
    ///
    /// Copy Generator's briefing file and written description are one step,
    /// not two: the toggle swaps between them, so splitting them would leave
    /// whichever is off showing an empty step.
    var steps: [String]? {
        switch self {
        case .contractPDF:
            ["Client", "Contractor", "Venue", "Service", "Signature"]
        case .copyGenerator:
            ["Briefing", "Pages", "Notes"]
        default:
            nil
        }
    }
}

struct FormToolConfiguration: Equatable {
    let kind: FormToolKind
    let actionTitle: String

    static func configuration(for toolID: String) -> FormToolConfiguration? {
        guard let kind = FormToolKind(rawValue: toolID) else { return nil }
        let actionTitle: String
        switch kind {
        case .whoisScan: actionTitle = "Run WHOIS Scan"
        case .dnsCheck: actionTitle = "Check DNS"
        case .siteSpeed: actionTitle = "Analyze Site Speed"
        case .wordpressInspector: actionTitle = "Inspect Site"
        case .policyGenerator: actionTitle = "Generate Policy"
        case .contractPDF: actionTitle = "Create Contract PDF"
        case .qrCode: actionTitle = "Create QR Code"
        case .copyGenerator: actionTitle = "Generate Copy"
        case .jsonCreator: actionTitle = "Create JSON"
        case .responsiveFontClamp: actionTitle = "Generate Clamp"
        case .htmlMinify: actionTitle = "Process HTML"
        case .jsMinify: actionTitle = "Process JavaScript"
        case .passwordGenerator: actionTitle = "Generate Password"
        case .colorConvert: actionTitle = "Convert Color"
        case .contrastCheck: actionTitle = "Check Contrast"
        case .waLink: actionTitle = "Create Link"
        }
        return .init(kind: kind, actionTitle: actionTitle)
    }
}
