import Foundation

/// Config publica do projeto Supabase (GoTrue/Auth). Valores vindos da nota
/// Maestri `envs` (fonte da verdade) — a anon key NAO e segredo de usuario:
/// e a mesma key que vai pra qualquer client (app mobile, site), protegida
/// por RLS no lado do Supabase, nao por sigilo. Mesma razao pela qual
/// `NimbusConfiguration.production.apiBaseURL` (NimbusAPI.swift) tambem e
/// uma constante hardcoded em vez de vir de Keychain/env var.
enum SupabaseConfiguration {
    static let url = URL(string: "https://vlmoidiqczbtshjaqewd.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZsbW9pZGlxY3pidHNoamFxZXdkIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY5NzUwODAsImV4cCI6MjEwMjU1MTA4MH0.zAZQT3nXo9SFFFO8lxc6m8IoCKo8RkAv2lImTWksHwk"

    /// Loopback HTTP local (RFC 8252) — nao mais um custom URL scheme. Porta
    /// fixa (nao efemera) porque precisa estar cadastrada, literal, na
    /// allow-list de Redirect URLs do dashboard Supabase; verificada livre
    /// neste ambiente de dev. So um processo pode segurar essa porta por
    /// vez — e por isso que rodar o build errado agora falha de forma
    /// visivel (`.failed`) em vez de abrir um segundo Nimbus (ver
    /// feature-spec: 'Registro: o que as ultimas 3 rodadas realmente eram').
    static let authRedirectPort: UInt16 = 53682
    static let authRedirectPath = "/auth-callback"
    static let authRedirectURL = URL(string: "http://127.0.0.1:\(authRedirectPort)\(authRedirectPath)")!
}