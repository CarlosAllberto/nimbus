import SwiftUI

/// The provider logos for the sign-in buttons. SF Symbols carries no
/// third-party brand marks, and each provider's sign-in guidelines ask for the
/// real logo, so these are the official paths — copied verbatim from the
/// Nimbus web app's own login page (`nimbus/app/(pages)/login/page.tsx`) so the
/// desktop buttons match the site rather than drifting from it.
struct ProviderBrandMark: View {
    let provider: SupabaseAuthProvider
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            ForEach(Array(Self.paths(for: provider).enumerated()), id: \.offset) { _, layer in
                SVGPath(command: layer.path)
                    .fill(layer.color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct Layer {
        let path: String
        let color: Color
    }

    private static func paths(for provider: SupabaseAuthProvider) -> [Layer] {
        switch provider {
        case .google:
            return [
                Layer(path: "M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z", color: Color(red: 0.259, green: 0.525, blue: 0.961)),
                Layer(path: "M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z", color: Color(red: 0.204, green: 0.659, blue: 0.329)),
                Layer(path: "M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z", color: Color(red: 0.988, green: 0.737, blue: 0.020)),
                Layer(path: "M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z", color: Color(red: 0.918, green: 0.263, blue: 0.212))
            ]
        case .facebook:
            return [
                Layer(path: "M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z", color: Color(red: 0.122, green: 0.522, blue: 1.0))
            ]
        case .github:
            return [
                // The site fills this with #111827, which disappears on a dark
                // window; the mark follows the label colour instead so it stays
                // legible in both appearances.
                Layer(path: "M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z", color: .primary)
            ]
        }
    }
}

/// Draws an SVG `path` command string, scaled to fill the view. Supports the
/// subset the brand marks above use — M/L/H/V/C/S/Z in both absolute and
/// relative form. Arcs and quadratic curves are deliberately absent: no mark
/// here uses them, and a half-working arc would fail silently. Unknown
/// commands stop parsing rather than guessing at the geometry.
struct SVGPath: Shape {
    let command: String
    /// The `viewBox` the path data was authored against; all three marks use
    /// `0 0 24 24`.
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var tokens = Tokenizer(command)
        var current = CGPoint.zero
        var start = CGPoint.zero
        // Reflection point for a smooth curve (`S`) that follows another curve.
        var lastControl: CGPoint?
        var verb: Character = " "

        while let next = tokens.nextVerbOrNumber() {
            switch next {
            case let .verb(character):
                verb = character
            case let .number(value):
                // A repeated coordinate set without a new letter repeats the
                // previous verb, which is how these paths are written.
                tokens.pushBack(value)
            }

            let relative = verb.isLowercase
            switch Character(verb.lowercased()) {
            case "m":
                guard let x = tokens.nextNumber(), let y = tokens.nextNumber() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                start = current
                path.move(to: current)
                lastControl = nil
                // Extra pairs after a moveto are implicit linetos.
                verb = relative ? "l" : "L"
            case "l":
                guard let x = tokens.nextNumber(), let y = tokens.nextNumber() else { return path }
                current = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addLine(to: current)
                lastControl = nil
            case "h":
                guard let x = tokens.nextNumber() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current)
                lastControl = nil
            case "v":
                guard let y = tokens.nextNumber() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current)
                lastControl = nil
            case "c":
                guard
                    let x1 = tokens.nextNumber(), let y1 = tokens.nextNumber(),
                    let x2 = tokens.nextNumber(), let y2 = tokens.nextNumber(),
                    let x = tokens.nextNumber(), let y = tokens.nextNumber()
                else { return path }
                let control1 = relative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let control2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: control1, control2: control2)
                lastControl = control2
                current = end
            case "s":
                guard
                    let x2 = tokens.nextNumber(), let y2 = tokens.nextNumber(),
                    let x = tokens.nextNumber(), let y = tokens.nextNumber()
                else { return path }
                let control2 = relative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                // Mirror the previous control point; with no previous curve the
                // spec says the control point coincides with the current point.
                let control1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                path.addCurve(to: end, control1: control1, control2: control2)
                lastControl = control2
                current = end
            case "z":
                path.closeSubpath()
                current = start
                lastControl = nil
            default:
                return path
            }
        }

        let scale = min(rect.width, rect.height) / viewBox
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
    }

    private struct Tokenizer {
        private let characters: [Character]
        private var index = 0
        private var pushedBack: CGFloat?

        init(_ string: String) {
            characters = Array(string)
        }

        enum Token {
            case verb(Character)
            case number(CGFloat)
        }

        mutating func pushBack(_ value: CGFloat) {
            pushedBack = value
        }

        mutating func nextVerbOrNumber() -> Token? {
            if pushedBack != nil { return nil }
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            if character.isLetter {
                index += 1
                return .verb(character)
            }
            guard let value = nextNumber() else { return nil }
            return .number(value)
        }

        mutating func nextNumber() -> CGFloat? {
            if let value = pushedBack {
                pushedBack = nil
                return value
            }
            skipSeparators()
            var digits = ""
            if index < characters.count, characters[index] == "-" || characters[index] == "+" {
                digits.append(characters[index])
                index += 1
            }
            while index < characters.count, characters[index].isNumber || characters[index] == "." {
                // A second dot starts a new number ("1.5.5" is two values), which
                // is legal SVG shorthand and appears in these paths.
                if characters[index] == ".", digits.contains(".") { break }
                digits.append(characters[index])
                index += 1
            }
            return Double(digits).map { CGFloat($0) }
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == "," || characters[index] == "\n" {
                index += 1
            }
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        ForEach(SupabaseAuthProvider.allCases) { provider in
            ProviderBrandMark(provider: provider, size: 40)
        }
    }
    .padding(30)
}
