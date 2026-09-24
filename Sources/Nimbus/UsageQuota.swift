import Foundation

enum UsageQuota {
    struct Snapshot: Sendable {
        let usageCount: Int
        /// Always the *effective* plan, resolved server-side through
        /// `effective_subscription_plan` — never the raw column. An expired
        /// trial and a past_due subscription both arrive here as "free",
        /// which is what the gate itself enforces.
        let subscriptionPlan: String
        /// Set only while a trial is actually still running; nil otherwise.
        let trialEndsAt: Date?

        /// So exibicao — ver feature-spec 'dailyLimit: display-only, nunca
        /// decisao'. NUNCA lido por `checkAndConsume`.
        /// The one phrasing for "how much of today is left", shared by the
        /// Account tab and the status-bar menu so the two never drift apart.
        var label: String {
            if let trialDaysLeft {
                return "Trial · \(trialDaysLeft) day\(trialDaysLeft == 1 ? "" : "s") left"
            }
            let planTitle = subscriptionPlan.capitalized
            guard let dailyLimit else { return "\(planTitle) · Unlimited" }
            return "\(planTitle) · \(usageCount) of \(dailyLimit) uses today"
        }

        /// Rounded up, so the last stretch under 24h still reads "1 day left"
        /// rather than "0". nil once the end date has passed — the row keeps
        /// `status = 'trialing'` forever, so the date is the only thing that
        /// decides, exactly as `effective_subscription_plan` does.
        var trialDaysLeft: Int? {
            guard let trialEndsAt, trialEndsAt > Date() else { return nil }
            return max(1, Int(ceil(trialEndsAt.timeIntervalSinceNow / 86_400)))
        }

        var dailyLimit: Int? {
            switch subscriptionPlan {
            case "free": 7
            case "basic": 20
            default: nil
            }
        }
    }

    enum GateResult {
        /// `consumed` says whether a unit was actually taken on the server.
        /// It is false on every fail-open path — not signed in, no token, the
        /// request failed — where the run is let through without anything
        /// having been counted. Only a real consumption may be released
        /// afterwards; refunding one that never happened hands out credit and
        /// undoes a unit the user legitimately spent earlier in the day.
        case allowed(consumed: Bool)
        case blocked(message: String)
    }

    static let upgradeURL = URL(string: "https://www.nimbushelp.com/#pricing")!

    /// Whether running this tool costs one of the day's uses. The one place
    /// that answers it, so the three call sites (`FileToolView`,
    /// `FormToolView`, `QuickDropView`) can't drift apart on what counts.
    ///
    /// A run is metered when it either hands back an artifact to keep or
    /// calls out to AI. Every file tool qualifies on the first count; among
    /// the form tools, QR Code returns a PNG/SVG and Contract PDF a PDF,
    /// while Contract PDF and Copy Generator are also the only two that
    /// reach Gemini (verified against `Sidecar/tools`).
    ///
    /// Everything else is a local, instant conversion or lookup whose answer
    /// just appears in the panel — Pick Color, Responsive Font Clamp,
    /// Password Generator, the colour tools. Those are the ones people reach
    /// for a dozen times an hour, and charging a use for them only made the
    /// app annoying without saving anything.
    ///
    /// The file half is derived rather than listed, so a new file tool is
    /// metered the moment it exists — the right default, since that's the
    /// expensive shape. The form half is named explicitly: a new form tool
    /// stays free until someone decides it shouldn't be.
    static func isMetered(toolID: String) -> Bool {
        if FileToolConfiguration.configuration(for: toolID) != nil { return true }
        return [FormToolKind.contractPDF, .copyGenerator, .qrCode]
            .contains { $0.rawValue == toolID }
    }

    /// Chamado uma vez por unidade a consumir (1x por execucao de form
    /// tool, 1x por arquivo de file tool — ver feature-spec). Falha
    /// ABERTA em qualquer problema pra sequer completar o check — ver
    /// feature-spec 'Falha de rede: falha aberta'.
    static func checkAndConsume() async -> GateResult {
        guard case let .signedIn(user) = await AuthSession.shared.state else { return .allowed(consumed: false) }
        guard let token = await readAccessToken() else { return .allowed(consumed: false) }

        guard let response = try? await consume(userID: user.id, accessToken: token) else {
            return .allowed(consumed: false)
        }
        let snapshot = Snapshot(
            usageCount: response.usageCount,
            subscriptionPlan: response.subscriptionPlan,
            trialEndsAt: response.trialEndsAt
        )
        await UsageIndicator.shared.update(snapshot)

        guard response.allowed else {
            return .blocked(message: blockedMessage(for: snapshot))
        }
        if response.subscriptionPlan == "pro" {
            // try_consume nao incrementa pro plano pro — paridade de
            // estatistica com o site, nunca gateia nada (fato 4).
            Task { try? await incrementProUsage(userID: user.id, accessToken: token) }
        }
        return .allowed(consumed: true)
    }

    /// Estorna a unidade que `checkAndConsume()` acabou de consumir,
    /// quando o processamento LOCAL que veio depois falhou ou foi
    /// cancelado — ver feature-spec 'Estorno em falha local'. Sem `await`
    /// no call site de proposito: nunca deve atrasar/travar o fluxo de
    /// erro que ja esta rodando.
    static func releaseOnFailure() {
        Task {
            guard case let .signedIn(user) = await AuthSession.shared.state else { return }
            guard let token = await readAccessToken() else { return }
            _ = try? await release(userID: user.id, accessToken: token)
        }
    }

    /// So leitura — indicador de Preferences. Falha so deixa o indicador
    /// no ultimo valor conhecido (ou vazio, se nunca resolveu nenhuma vez).
    static func fetchCurrent() async -> Snapshot? {
        guard case let .signedIn(user) = await AuthSession.shared.state else { return nil }
        guard let token = await readAccessToken() else { return nil }
        guard let snapshot = try? await fetchAndReset(userID: user.id, accessToken: token) else { return nil }
        await UsageIndicator.shared.update(snapshot)
        return snapshot
    }

    // MARK: - Rede

    private struct ConsumeResponse {
        let allowed: Bool
        let usageCount: Int
        let subscriptionPlan: String
        let trialEndsAt: Date?
    }

    private static func consume(userID: String, accessToken: String) async throws -> ConsumeResponse {
        let request = try rpcRequest(name: "try_consume_daily_usage", userID: userID, accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try decodeConsumeResponse(from: data)
    }

    private static func incrementProUsage(userID: String, accessToken: String) async throws {
        let request = try rpcRequest(name: "increment_usage", userID: userID, accessToken: accessToken)
        _ = try await URLSession.shared.data(for: request)
    }

    private static func release(userID: String, accessToken: String) async throws {
        let request = try rpcRequest(name: "release_daily_usage", userID: userID, accessToken: accessToken)
        _ = try await URLSession.shared.data(for: request)
    }

    /// `get_usage_snapshot` rather than reading the `users` row directly:
    /// the row carries the *raw* plan, so an expired trial (or a past_due
    /// subscription) read straight off it displayed as "Pro · Unlimited"
    /// while the gate had already dropped the user to free. The RPC resolves
    /// the plan through the same `effective_subscription_plan` the gate uses,
    /// so the indicator can't disagree with what actually happens on a run.
    /// It also calls `reset_daily_usage_if_needed` itself, which the client
    /// used to have to do as a separate round trip (fact 3; parameter name
    /// confirmed in the site's `hooks/use-subscription-profile.ts:27`).
    private static func fetchAndReset(userID: String, accessToken: String) async throws -> Snapshot {
        let request = try rpcRequest(name: "get_usage_snapshot", userID: userID, accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(data: data, response: response)
        return try decodeUsersRow(from: data)
    }

    private static func rpcRequest(name: String, userID: String, accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: SupabaseConfiguration.url.appending(path: "/rest/v1/rpc/\(name)"))
        request.httpMethod = "POST"
        request.setValue(SupabaseConfiguration.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["user_id": userID])
        return request
    }

    private static func checkStatus(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseAuthError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "Unknown error")
        }
    }

    /// Toda `TABLE(...)`/rota de tabela do PostgREST devolve ARRAY — ver
    /// fato 2. Nunca decodificar como objeto solto.
    private static func decodeConsumeResponse(from data: Data) throws -> ConsumeResponse {
        guard
            let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let row = array.first,
            let allowed = row["allowed"] as? Bool,
            let usageCount = row["usage_count"] as? Int,
            let plan = row["subscription_plan"] as? String
        else { throw SupabaseAuthError.invalidResponse }
        return ConsumeResponse(
            allowed: allowed,
            usageCount: usageCount,
            subscriptionPlan: plan,
            trialEndsAt: trialEndsAt(in: row)
        )
    }

    private static func decodeUsersRow(from data: Data) throws -> Snapshot {
        guard
            let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let row = array.first,
            let usageCount = row["usage_count"] as? Int,
            let plan = row["subscription_plan"] as? String
        else { throw SupabaseAuthError.invalidResponse }
        return Snapshot(usageCount: usageCount, subscriptionPlan: plan, trialEndsAt: trialEndsAt(in: row))
    }

    /// Null whenever no trial is running, which is the common case — so a
    /// missing or unparseable value is simply "no trial", never an error.
    /// Postgres hands back fractional seconds ("...T20:50:30.549176+00:00")
    /// and `ISO8601DateFormatter` needs to be told about them, so both
    /// spellings are tried.
    private static func trialEndsAt(in row: [String: Any]) -> Date? {
        guard let raw = row["trial_ends_at"] as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: raw) ?? plain.date(from: raw)
    }

    /// Fora do MainActor de proposito — ver feature-spec 'Por que o token
    /// nao passa por AuthSession'.
    private static func readAccessToken() async -> String? {
        await Task.detached {
            (try? KeychainTokenStore().accessToken()) ?? nil
        }.value
    }

    private static func blockedMessage(for snapshot: Snapshot) -> String {
        let planTitle = snapshot.subscriptionPlan.capitalized
        if let limit = snapshot.dailyLimit {
            return "You've used all \(limit) of your \(planTitle) plan's daily tool runs. Upgrade for more, or try again tomorrow. Usage resets at midnight UTC."
        }
        return "Daily usage limit reached. Upgrade for more, or try again tomorrow. Usage resets at midnight UTC."
    }
}

/// Ponte AppKit/qualquer-view -> Preferences, mesmo padrao
/// `@MainActor ObservableObject` singleton que `AuthSession`/
/// `ToolLauncher` ja usam. `UsageQuota` atualiza depois de cada
/// `checkAndConsume()`/`fetchCurrent()`; `PreferencesView` so le.
@MainActor
final class UsageIndicator: ObservableObject {
    static let shared = UsageIndicator()
    private init() {}

    @Published private(set) var snapshot: UsageQuota.Snapshot?

    func update(_ snapshot: UsageQuota.Snapshot?) {
        guard let snapshot else { return }
        self.snapshot = snapshot
    }
}