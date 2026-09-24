import Foundation

/// Ponte AppKit -> SwiftUI pra reabrir a janela principal. Com `Window(id:)`
/// no lugar de `WindowGroup`, o SwiftUI so cria a instancia da Scene uma
/// vez na vida do app; depois que o usuario fecha a janela via botao
/// vermelho/⌘W, `NSApp.windows.first` nao a encontra mais, e o `NSWindow`
/// cacheado em `AppDelegate.mainWindow` nao tem garantia documentada de
/// voltar a receber conteudo depois de uma chamada pura de
/// `makeKeyAndOrderFront` -- relatos consistentes em foruns (Apple
/// Developer Forums 782887) confirmam isso. A unica via documentada pela
/// Apple pra reabrir uma `Window(id:)` depois de fechada e
/// `@Environment(\.openWindow)` -> `openWindow(id: ...)`, que vive dentro de
/// uma `View` SwiftUI.
///
/// `MainWindowView` (unica View que ocupa essa Scene) captura a action do
/// `openWindow` no `.onAppear` e deposita aqui; `AppDelegate.showMainWindow()`
/// chama `openMain()` quando o caminho via `NSWindow` cacheado falha.
///
/// Mesmo padrao que `ToolLauncher`/`AuthSession`: `@MainActor`
/// `ObservableObject` singleton.
@MainActor
final class MainWindowOpener: ObservableObject {
    static let shared = MainWindowOpener()
    private init() {}

    /// Captured from `@Environment(\.openWindow)` by the live `MainWindowView`
    /// instance. Nil when the view is not on screen -- `openMain()` in that
    /// case is a no-op (and `showMainWindow()` falls back to the
    /// `NSApp.windows` path).
    private var openAction: (() -> Void)?

    func registerOpenAction(_ action: @escaping () -> Void) {
        openAction = action
    }

    func openMain() {
        openAction?()
    }
}