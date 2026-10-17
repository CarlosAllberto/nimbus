import Foundation

extension CompressionLevel: Identifiable {
    var id: Self { self }

    var title: String {
        switch self {
        case .low: String(localized: "Low compression", bundle: .l10n)
        case .high: String(localized: "High compression", bundle: .l10n)
        case .lossless: String(localized: "Lossless", bundle: .l10n)
        }
    }

    var detail: String {
        switch self {
        case .low: String(localized: "Best quality", bundle: .l10n)
        case .high: String(localized: "Smallest file", bundle: .l10n)
        case .lossless: String(localized: "Keeps every pixel", bundle: .l10n)
        }
    }
}

/// The one setting a tool takes, chosen in the option list after a drop.
enum ToolOption: Sendable, Hashable {
    case level(CompressionLevel)
    case format(ImageConverter.Format)
    case videoFormat(VideoConverter.Format)
    case safeMargin(Bool)
}

/// One row of the option list.
struct ToolChoice: Identifiable {
    let title: String
    let detail: String?
    let option: ToolOption
    var id: String { title }
}

extension NimbusTool {
    /// Empty for tools that run straight away.
    var choices: [ToolChoice] {
        switch id {
        case "to-webp", "to-webm":
            CompressionLevel.allCases.map { ToolChoice(title: $0.title, detail: $0.detail, option: .level($0)) }
        case "convert":
            ImageConverter.Format.allCases.map { ToolChoice(title: $0.rawValue.uppercased(), detail: nil, option: .format($0)) }
        case "video-convert":
            VideoConverter.Format.allCases.map { ToolChoice(title: $0.rawValue.uppercased(), detail: nil, option: .videoFormat($0)) }
        case "ico":
            [ToolChoice(title: String(localized: "No margin", bundle: .l10n), detail: String(localized: "Icon fills the square", bundle: .l10n), option: .safeMargin(false)),
             ToolChoice(title: String(localized: "Safe margin", bundle: .l10n), detail: String(localized: "Room for rounded tabs", bundle: .l10n), option: .safeMargin(true))]
        default:
            []
        }
    }

    /// Index into `choices` of the default saved in Preferences.
    var defaultChoiceIndex: Int {
        let defaults = UserDefaults.standard
        let wanted: ToolOption? = switch id {
        case "to-webp": .level(CompressionLevel(rawValue: defaults.string(forKey: QuickDropPreferenceKey.webPCompression) ?? "") ?? .low)
        case "to-webm": .level(CompressionLevel(rawValue: defaults.string(forKey: QuickDropPreferenceKey.webMCompression) ?? "") ?? .low)
        case "convert": .format(ImageConverter.Format(rawValue: defaults.string(forKey: QuickDropPreferenceKey.convertFormat) ?? "") ?? .png)
        case "video-convert": .videoFormat(VideoConverter.Format(rawValue: defaults.string(forKey: QuickDropPreferenceKey.videoConvertFormat) ?? "") ?? .mp4)
        case "ico": .safeMargin(defaults.bool(forKey: QuickDropPreferenceKey.icoSafeMargin))
        default: nil
        }
        return choices.firstIndex { $0.option == wanted } ?? 0
    }
}

enum ToolRunnerError: LocalizedError {
    case unknownTool(String)

    var errorDescription: String? {
        switch self {
        case let .unknownTool(id): String(localized: "Unknown tool “\(id)”.", bundle: .l10n)
        }
    }
}

/// Runs one Quick Drop tool on one file and returns the file it wrote.
/// `option` is nil for tools with no setting.
protocol ToolRunner: Sendable {
    func run(tool: NimbusTool, file: URL, option: ToolOption?) async throws -> URL
}

/// The native engines under `Engines/`. A missing or mismatched option falls
/// back to the engine's default.
struct EngineToolRunner: ToolRunner {
    func run(tool: NimbusTool, file: URL, option: ToolOption?) async throws -> URL {
        switch (tool.id, option) {
        case let ("to-webp", .level(level)?): try await ImageCompressor.run(input: file, level: level)
        case ("to-webp", _): try await ImageCompressor.run(input: file)
        case let ("to-webm", .level(level)?): try await VideoCompressor.run(input: file, level: level)
        case ("to-webm", _): try await VideoCompressor.run(input: file)
        case let ("ico", .safeMargin(margin)?): try await FaviconMaker.run(input: file, safeMargin: margin)
        case ("ico", _): try await FaviconMaker.run(input: file)
        case ("trim-image", _): try await ImageTrimmer.run(input: file)
        case let ("convert", .format(format)?): try await ImageConverter.run(input: file, format: format)
        case ("convert", _): try await ImageConverter.run(input: file, format: .png)
        case let ("video-convert", .videoFormat(format)?): try await VideoConverter.run(input: file, format: format)
        case ("video-convert", _): try await VideoConverter.run(input: file, format: .mp4)
        default: throw ToolRunnerError.unknownTool(tool.id)
        }
    }
}
