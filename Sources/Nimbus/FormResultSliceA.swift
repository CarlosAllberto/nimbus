import SwiftUI
import UniformTypeIdentifiers

// MARK: - Slice A Decodable shapes

struct WhoisResult: Decodable {
    let domain: String
    let raw: String
    let parsed: [String: String]
}

struct DnsCheckResult: Decodable {
    let domain: String
    let type: String
    let results: [DnsProviderResult]
}

struct DnsProviderResult: Decodable {
    let provider: String
    let server: String
    let status: String
    let answers: [DnsAnswer]
    let error: String?
}

struct DnsAnswer: Decodable {
    let name: String
    let type: String
    let ttl: Int
    let data: String
}

struct SiteSpeedResult: Decodable {
    let source: String
    let requestedUrl: String
    let finalUrl: String
    let strategy: String
    let scores: SiteSpeedScores
    let metrics: [SiteSpeedMetric]
}

struct SiteSpeedScores: Decodable {
    let performance: Int?
    let accessibility: Int?
    let bestPractices: Int?
    let seo: Int?
}

struct SiteSpeedMetric: Decodable {
    let id: String
    let displayValue: String
}

struct WordPressInspectorResult: Decodable {
    let source: String
    let requestedUrl: String
    let finalUrl: String
    let looksLikeWordPress: Bool
    let core: WordPressCoreInfo
    let plugins: [WordPressComponentInfo]
    let themes: [WordPressComponentInfo]
    let warnings: [String]
    let attribution: String
}

struct WordPressCoreInfo: Decodable {
    let version: String?
    let cves: [WordPressCVEInfo]
    let otherSources: [WordPressSourceInfo]
    let vulnDbError: String?
}

struct WordPressComponentInfo: Decodable {
    let slug: String
    let version: String?
    let versionSource: String?
    let displayName: String?
    let cves: [WordPressCVEInfo]
    let otherSources: [WordPressSourceInfo]
    let vulnDbError: String?
    let versionError: String?
    let cveScanSkipped: Bool
}

struct WordPressCVEInfo: Decodable {
    let id: String
    let link: String?
    let title: String
    let published: String?
}

struct WordPressSourceInfo: Decodable {
    let id: String
    let name: String
    let link: String?
    let published: String?
}

struct PolicyGeneratorResult: Decodable {
    let privacyPolicy: PolicyDocumentVariants
    let termsOfConditions: PolicyDocumentVariants
}

struct PolicyDocumentVariants: Decodable {
    let text: String
    let html: String
    let react: String
}

/// Composes the per-tool result panel for every form tool whose
/// `FormToolKind` belongs to slice A (`.sliceA`): `whois-scan`, `dns-check`,
/// `site-speed`, `wordpress-inspector`, `policy-generator`, plus
/// `contract-pdf`/`qrcode` defensively — those last two never actually reach
/// here because the file branch returns before routing (they always come
/// back from the sidecar as a binary payload, not `application/json`).
///
/// `contract-pdf`/`qrcode` keep their `default:` for the rare case where the
/// sidecar's content-type detection ever misroutes them; the fallback is the
/// same `RawJSONFallbackView` every unrecognized id lands on.
struct FormResultSliceA: View {
    let kind: FormToolKind
    let json: Data

    @State private var selectedDocument = 0

    var body: some View {
        switch kind {
        case .whoisScan:
            whoisScan
        case .dnsCheck:
            dnsCheck
        case .siteSpeed:
            siteSpeed
        case .wordpressInspector:
            wordpressInspector
        case .policyGenerator:
            policyGenerator
        default:
            // contractPDF / qrCode defensively — they normally come back as
            // `.file` and never reach this router.
            RawJSONFallbackView(json: json)
        }
    }

    /// Decode helper that every composer ends up wanting: try the JSON
    /// `Decoder` against the typed shape, fall back to the raw panel on
    /// failure so a single bad field doesn't kill the whole composer.
    @ViewBuilder
    func decoded<T: Decodable, V: View>(_ type: T.Type, @ViewBuilder content: (T) -> V) -> some View {
        if let value = try? JSONDecoder().decode(T.self, from: json) {
            content(value)
        } else {
            RawJSONFallbackView(json: json)
        }
    }

    // MARK: whois-scan

    @ViewBuilder
    private var whoisScan: some View {
        decoded(WhoisResult.self) { result in
            VStack(alignment: .leading, spacing: 14) {
                Text("Domain: \(result.domain)")
                    .font(.headline)
                if !result.parsed.isEmpty {
                    KeyValueTable(
                        rows: result.parsed
                            .sorted { $0.key < $1.key }
                            .map { (label: $0.key, value: $0.value) }
                    )
                }
                DisclosureGroup("Raw response") {
                    Text(result.raw)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Spacer(minLength: 0)
                        CopyButton(text: result.raw)
                    }
                }
            }
        }
    }

    // MARK: dns-check

    @ViewBuilder
    private var dnsCheck: some View {
        decoded(DnsCheckResult.self) { result in
            VStack(alignment: .leading, spacing: 14) {
                Text("\(result.domain) · \(result.type)")
                    .font(.headline)

                ForEach(Array(result.results.enumerated()), id: \.offset) { _, provider in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            FormSectionHeader(title: "\(provider.provider) (\(provider.server))")
                            Spacer(minLength: 0)
                            BadgeView(
                                text: provider.status == "ok" ? "OK" : "Error",
                                tone: provider.status == "ok" ? .pass : .fail
                            )
                        }
                        if let error = provider.error {
                            Text(error)
                                .foregroundStyle(.secondary)
                        } else if provider.answers.isEmpty {
                            Text("No records found.")
                                .foregroundStyle(.secondary)
                        } else {
                            KeyValueTable(
                                rows: provider.answers.map { answer in
                                    (label: answer.type, value: "\(answer.data)  · TTL \(answer.ttl)s")
                                },
                                valuesAreMonospaced: true
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: site-speed

    @ViewBuilder
    private var siteSpeed: some View {
        decoded(SiteSpeedResult.self) { result in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(result.finalUrl)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    BadgeView(text: result.strategy.capitalized, tone: .neutral)
                }

                HStack(spacing: 10) {
                    scoreBadge("Performance", result.scores.performance)
                    scoreBadge("Accessibility", result.scores.accessibility)
                    scoreBadge("Best Practices", result.scores.bestPractices)
                    scoreBadge("SEO", result.scores.seo)
                }

                if !result.metrics.isEmpty {
                    KeyValueTable(
                        rows: result.metrics.map {
                            (label: kebabToTitle($0.id), value: $0.displayValue)
                        }
                    )
                }
            }
        }
    }

    /// Local mapping from PageSpeed's kebab-case metric IDs to display titles.
    /// Generic — splits on `-`, capitalizes each word, joins with space — so it
    /// works for any future metric the API adds without changing the composer.
    private func kebabToTitle(_ id: String) -> String {
        id.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Score 50–89 is neither pass nor fail; uses the additive `BadgeTone.warn`
    /// introduced in `FormControls.swift` for this composer.
    private func scoreBadge(_ label: String, _ score: Int?) -> some View {
        let tone: BadgeTone
        let display: String
        if let score {
            display = "\(score)"
            if score >= 90 {
                tone = .pass
            } else if score >= 50 {
                tone = .warn
            } else {
                tone = .fail
            }
        } else {
            display = "—"
            tone = .neutral
        }
        return VStack(spacing: 4) {
            BadgeView(text: display, tone: tone)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: wordpress-inspector

    @ViewBuilder
    private var wordpressInspector: some View {
        decoded(WordPressInspectorResult.self) { result in
            VStack(alignment: .leading, spacing: 14) {
                if !result.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(result.warnings.enumerated()), id: \.offset) { _, warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                FormSectionHeader(title: "Core")
                WordPressComponentRow(
                    title: "WordPress \(result.core.version ?? "?")",
                    cveCount: result.core.cves.count,
                    rows: coreRows(result.core),
                    cves: result.core.cves
                )

                FormSectionHeader(title: "Plugins (\(result.plugins.count))")
                ForEach(Array(result.plugins.enumerated()), id: \.offset) { _, plugin in
                    WordPressComponentRow(
                        title: "\(plugin.displayName ?? plugin.slug) \(plugin.version ?? "?")",
                        cveCount: plugin.cves.count,
                        rows: componentRows(plugin),
                        cves: plugin.cves
                    )
                }

                FormSectionHeader(title: "Themes (\(result.themes.count))")
                ForEach(Array(result.themes.enumerated()), id: \.offset) { _, theme in
                    WordPressComponentRow(
                        title: "\(theme.displayName ?? theme.slug) \(theme.version ?? "?")",
                        cveCount: theme.cves.count,
                        rows: componentRows(theme),
                        cves: theme.cves
                    )
                }

                Text(result.attribution)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Core has no slug/versionSource/versionError fields — only the version
    /// itself plus CVEs/otherSources (other sources are attribution noise here).
    private func coreRows(_ core: WordPressCoreInfo) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        if let v = core.version { rows.append(("Version", v)) }
        if let e = core.vulnDbError { rows.append(("Vuln DB", e)) }
        return rows
    }

    private func componentRows(_ c: WordPressComponentInfo) -> [(label: String, value: String)] {
        var rows: [(String, String)] = []
        rows.append(("Slug", c.slug))
        if let v = c.version { rows.append(("Version", v)) }
        if let s = c.versionSource { rows.append(("Source", s)) }
        if let e = c.versionError { rows.append(("Version Error", e)) }
        return rows
    }

    // MARK: policy-generator

    @ViewBuilder
    private var policyGenerator: some View {
        decoded(PolicyGeneratorResult.self) { result in
            VStack(alignment: .leading, spacing: 12) {
                Picker("Document", selection: $selectedDocument) {
                    Text("Privacy Policy").tag(0)
                    Text("Terms & Conditions").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                policyTabs(result: result)
            }
        }
    }

    @ViewBuilder
    private func policyTabs(result: PolicyGeneratorResult) -> some View {
        let variants = selectedDocument == 0 ? result.privacyPolicy : result.termsOfConditions
        let base = selectedDocument == 0 ? "privacy-policy" : "terms-and-conditions"
        TabbedTextView(tabs: [
            FormTextTab(title: "Text", content: variants.text, filename: "\(base).txt", contentType: .plainText),
            FormTextTab(title: "HTML", content: variants.html, filename: "\(base).html", contentType: .html),
            FormTextTab(title: "React", content: variants.react, filename: "\(base).jsx", contentType: UTType(filenameExtension: "jsx") ?? .plainText),
        ], maxHeight: .infinity)
    }
}

// MARK: - WordPress sub-component (only this composer uses)

/// DisclosureGroup with a title, a CVE-count badge, an optional key/value
/// table, and a list of CVE links. Lives next to the composer because no
/// other tool's panel needs this shape.
private struct WordPressComponentRow: View {
    let title: String
    let cveCount: Int
    let rows: [(label: String, value: String)]
    let cves: [WordPressCVEInfo]

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                if !rows.isEmpty {
                    KeyValueTable(rows: rows)
                }
                if !cves.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(cves.enumerated()), id: \.offset) { _, cve in
                            cveLink(for: cve)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer(minLength: 0)
                BadgeView(
                    text: cveCount > 0 ? "\(cveCount) CVE\(cveCount == 1 ? "" : "s")" : "No CVEs",
                    tone: cveCount > 0 ? .fail : .pass
                )
            }
        }
    }

    @ViewBuilder
    private func cveLink(for cve: WordPressCVEInfo) -> some View {
        if let link = cve.link, let url = URL(string: link) {
            Link(cve.title, destination: url)
        } else {
            Text(cve.title)
        }
    }
}