# Archived feature-spec (snapshot 2026-09-18)

Live eyedropper contract. Landed in 2c05803, later hidden in 2db6927 (system sampler used instead). Useful if the custom eyedropper is revived.

# Feature: Conta-gotas próprio com hex ao vivo (substitui NSColorSampler)

Pick Color (rodada anterior) usa `NSColorSampler` — só entrega a cor no
clique, sem preview ao mover o cursor. Usuário quer hex em tempo real.
Confirmado no header do SDK: `NSColorSampler` só expõe
`showSamplerWithSelectionHandler`, sem hover/stream — por isso vira
conta-gotas próprio via ScreenCaptureKit.

## Fatos medidos (usuário, base — não re-derivar)

1. `CGWindowListCreateImage` é **UNAVAILABLE** neste SDK (macOS 26.5) — erro
   de compilação, não warning ("Please use ScreenCaptureKit instead"). Sem
   caminho por CoreGraphics clássico.
2. `SCScreenshotManager.captureImage` (pontual): média 116ms/captura 60x60
   (~9fps) — não serve pra lupa ao vivo.
3. `SCStream` (contínuo) **serve**: `sourceRect` 64x64, `minimumFrameInterval`
   1/60, `queueDepth` 3 → 51fps reais medidos (110 frames/2.2s). Pixel lido
   direto do `CVPixelBuffer`, formato **BGRA** (`p[2],p[1],p[0] = R,G,B`) —
   testado, retornou `#C7C7C7` correto.
4. Permissão de Gravação de Tela (TCC), amarrada à IDENTIDADE do app.
   Nimbus está assinado ad-hoc (`Signature=adhoc`, sem `TeamIdentifier`) —
   tende a pedir de novo a cada rebuild em dev, mesma classe de problema já
   documentada com o diálogo do Keychain (rodada do login obrigatório).
   `CGPreflightScreenCaptureAccess()`/`CGRequestScreenCaptureAccess()`
   confirmados existentes e funcionais.

## Achado meu, verificado agora (o usuário pediu pra checar, não afirmar)

**`Info.plist` PRECISA de `NSScreenCaptureUsageDescription`.** Diferente
de outras permissões TCC no macOS, o app pode ser **terminado pelo sistema**
se disparar o prompt de Gravação de Tela sem essa chave — não é só um
prompt genérico sem texto customizado, é um crash de verdade. Confirmado
via busca (Apple Developer Docs de `CGRequestScreenCaptureAccess()` +
relato de bug real de outro app open-source que tomou esse crash por
faltar a chave). Adicionar:

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>Nimbus uses screen recording access to power the Pick Color eyedropper, which previews colors live as you move the cursor.</string>
```

## Desenho: por que overlay transparente por tela + monitor local (sem Acessibilidade)

Um clique em QUALQUER pixel da tela — inclusive sobre janelas de outros
apps — só chega no nosso processo via `NSEvent.addLocalMonitorForEvents`
se **algum window nosso estiver presente naquele ponto** (monitor local só
vê eventos já endereçados a uma janela do próprio app; um monitor GLOBAL
veria em qualquer lugar, mas exige Acessibilidade — é exatamente o que o
usuário pediu pra evitar). Solução: **1 `NSPanel` transparente por
`NSScreen.screens`**, cobrindo cada tela inteira, `level = .screenSaver`
(acima de tudo, inclusive outros apps), sem desenhar nada
(`isOpaque = false`, `backgroundColor = .clear` — uma janela totalmente
transparente não contribui pixel nenhum ao framebuffer composto, então
nunca aparece na própria captura nem tapa visualmente o que está por
baixo). Essas N janelas são só a "superfície de clique" — o clique em
qualquer uma delas é pego por **1 `NSEvent.addLocalMonitorForEvents`
único**, instalado uma vez ao iniciar a sessão, que trata `.leftMouseDown`
(escolhe) e `.keyDown`+Esc (cancela) — independente de qual das N janelas
tecnicamente recebeu o evento bruto, porque o monitor vê tudo que chega
pro app inteiro.

O **movimento contínuo** (lupa seguindo o cursor) **não depende de evento
de mouse nenhum** — anda de carona no próprio callback de frame do
`SCStream` (que já dispara a ~51fps medidos): a cada frame, relê
`NSEvent.mouseLocation` (API direta, sempre disponível, não depende de
roteamento de evento) e reposiciona a lupa + recentraliza o `sourceRect`.
Mais robusto que depender de `mouseMoved` cruzando N janelas em N telas, e
reaproveita dado que já estamos recebendo de qualquer forma.

## Multi-monitor e Retina — precisão de pixel

- **Qual tela o cursor está**: `NSScreen.screens.first { $0.frame.contains(mouseLocation) }`.
- **Qual `SCDisplay` corresponde a essa `NSScreen`**: via `CGDirectDisplayID`
  (`screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]`),
  comparado contra `SCDisplay.displayID` de `SCShareableContent.current.displays`
  — forma padrão e estável de correlacionar os dois.
- **Trocar de tela**: `SCStream` é amarrado a 1 `SCContentFilter` de 1
  display na criação — não dá pra "trocar" o display de um stream vivo.
  Cruzar de tela para de tela = para o stream atual e cria um novo
  filtrado pro display novo. Aceitável: cruzar de monitor é um movimento
  grande, não fino — o pequeno delay de recriar o stream nessa borda não
  compromete a experiência de seguir o cursor DENTRO de uma tela.
- **Dentro da mesma tela**: `stream.updateConfiguration(_:)` (existe,
  confirmado pelo usuário) recentraliza o `sourceRect` — só chamado
  quando a origem muda de verdade (comparação simples), pra não
  reconfigurar a 51fps à toa quando o cursor está parado.
- **⚠️ Ponto de maior risco, NÃO verificado contra cursor em movimento**
  (a medição do usuário usou um `sourceRect` fixo, que não revela erro de
  conversão de coordenada): `NSScreen.frame`/`NSEvent.mouseLocation` usam
  origem INFERIOR-esquerda com Y crescendo pra CIMA (convenção AppKit);
  `sourceRect` do ScreenCaptureKit usa a convenção de `CGDisplayBounds`/
  `SCDisplay` — origem SUPERIOR-esquerda, Y crescendo pra BAIXO. A
  conversão abaixo inverte Y explicitamente. **Se a lupa aparecer
  capturando um pixel deslocado do cursor de verdade, este é o primeiro
  lugar a olhar** — não dá pra confirmar sem rodar com GUI.
- **Retina**: `configuration.width`/`.height` (dimensões do
  `CVPixelBuffer` de saída) são em PIXELS; `sourceRect` é em PONTOS. Sem
  multiplicar por `screen.backingScaleFactor`, o buffer sairia
  sub-amostrado (menos pixels reais que a tela tem naquela região) e a cor
  lida no centro não seria o pixel físico exato sob o cursor — exatamente
  o tipo de erro que quebraria "precisão de pixel é o ponto da
  ferramenta". `width = height = Int(64 * screen.backingScaleFactor)`.

## Ciclo de vida do `SCStream`

Sobe só quando `EyedropperController.start()` é chamado (nunca antes —
sem stream ocioso). Derruba em QUALQUER saída: escolher (clique), cancelar
(Esc ou chamada programática), ou o próprio `SCStream` reportar erro
(`SCStreamDelegate.didStopWithError` — trata como cancelamento, nunca
deixa a sessão pendurada num estado quebrado). Um só `teardown()` central
faz tudo: para o stream, remove o monitor de evento, fecha as N+1 janelas
(overlays + lupa), restaura o cursor — chamado de todos os caminhos de
saída, nunca duplicado.

## Degradação sem permissão — decisão

**Mantém `NSColorSampler` como caminho alternativo, sempre visível como
"Use System Picker"** (não escondido atrás de um estado de erro) — mesma
recomendação do usuário, aceita. Porquê: (1) não precisa de permissão
nenhuma, por ser serviço do sistema — funciona hoje, sem dependência de
TCC/assinatura; (2) esconder completamente a ferramenta até a permissão
ser concedida deixaria Pick Color inutilizável bloqueado por um detalhe
de ambiente de dev (assinatura ad-hoc re-pedindo a cada rebuild) que não
tem nada a ver com a capacidade real da ferramenta. Sem permissão: mostra
um aviso curto explicando o ganho (preview ao vivo) + botão "Grant
Access" (chama `CGRequestScreenCaptureAccess()` — só reabre o prompt do
sistema na 1ª vez; se já foi negado antes, essa chamada não reabre nada,
então também tem um botão "Open System Settings" com o deep-link padrão
da Apple `x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`
— não testável aqui, mas é URL scheme documentado e estável da Apple).
**Nota de ambiente**: mesmo depois de conceder, `CGPreflightScreenCaptureAccess()`
pode continuar `false` pro processo JÁ RODANDO até o Nimbus ser reaberto
(comportamento conhecido do TCC pra Gravação de Tela) — a UI reconfere ao
reaparecer (`.onAppear`), então voltar de System Settings pro app já
resolve sozinho SE o processo não precisar reiniciar; se precisar, o
aviso continua mostrando "Grant Access" e o usuário só percebe que precisa
reabrir o Nimbus na prática (não dá pra distinguir programaticamente essas
2 situações só com a API disponível).

## Onde a cor termina — inalterado

Painel de resultado (hex/RGB/HSL + copiar, `SwatchView`+`KeyValueTable` de
`FormControls.swift`) da rodada anterior **não muda**. O novo caminho ao
vivo e o `NSColorSampler` de fallback convergem no MESMO
`@State private var pickedColor: NSColor?` que já existe — só a origem da
cor muda, o resto do fluxo é o mesmo código.

## Quota — mantido

Pick Color continua sem consumir. Nada nesta rodada muda isso — nem o
caminho ao vivo nem o fallback passam por `FileToolView`/
`FormToolView.runTool()`, então nenhum dos dois chega em
`UsageQuota.checkAndConsume()` (mesma razão estrutural documentada na
rodada anterior).

---

## Corte de slices (2 implementers, ownership de arquivo travado)

- **Slice A — Rivet — "Motor de captura".** Ownership:
  - `Sources/Nimbus/Eyedropper.swift` (novo — `EyedropperController`,
    `EyedropperOverlayPanel`, `EyedropperLoupePanel`, todo o pipeline
    SCStream/permissão)

- **Slice B — Wren — "Integração no Pick Color + permissão na UI + Info.plist".** Ownership:
  - `Sources/Nimbus/NativeToolView.swift` (edit — `PickColorView` ganha
    os estados de permissão e o botão "Pick a Color (Live)"/"Use System
    Picker"; painel de resultado INTOCADO)
  - `Sources/Nimbus/Info.plist` (edit — `NSScreenCaptureUsageDescription`)

Nenhum arquivo tocado pelas duas. Dependência cruzada é só de assinatura —
Slice B usa `EyedropperController.shared`/`.isAuthorized()`/
`.requestAccess()`/`.systemSettingsURL`/`.start(onPick:onCancel:)` que a
Slice A cria. Slice A não depende de nada da Slice B — podem rodar em
paralelo, mas Slice B só consegue TESTAR de verdade (mesmo que só por
leitura) depois que a assinatura de `EyedropperController` estiver
estável; a assinatura abaixo já está fechada, então isso não bloqueia o
início do trabalho de nenhuma das duas.

---

## Avisos de processo — releitura obrigatória antes de reportar qualquer coisa

1. `Eyedropper.swift` (único `.swift` novo) precisa das DUAS entradas
   ligadas no `Nimbus.xcodeproj/project.pbxproj` (`PBXFileReference` +
   `PBXBuildFile` + grupo + Sources phase). `swift build` NÃO pega a
   falta disso — só `xcodebuild` pega.
2. Validar SEMPRE com os 2: `swift build` E
   `xcodebuild -project Nimbus.xcodeproj -scheme Nimbus -configuration Debug -destination 'platform=macOS' build`.
3. **Proibido reportar "verificado ao vivo" sem medição real — e aqui
   isso vale em dobro.** Ninguém nesta sessão tem GUI. A parte visual (lupa
   seguindo o cursor, precisão de pixel, permissão sendo pedida de
   verdade) só o usuário consegue julgar rodando o app. Relato tem que
   dizer exatamente o que foi verificado (leitura de código + build) e o
   que NÃO foi (comportamento em runtime) — sem ambiguidade.

---

## Slice A — Rivet — detalhado

### `Sources/Nimbus/Eyedropper.swift` — novo arquivo

```swift
import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreImage
import Carbon.HIToolbox

enum EyedropperError: Error, LocalizedError {
    case screenRecordingNotAuthorized
    var errorDescription: String? {
        "Screen Recording access is required for the live eyedropper."
    }
}

/// Um conta-gotas de uso único: overlay transparente clicável em cada tela,
/// um painel de lupa pequeno seguindo o cursor, e um SCStream (ScreenCaptureKit)
/// capturando uma região minúscula ao redor dele a ~50fps — configuração
/// medida e funcional (ver feature-spec 'Fatos medidos'): sourceRect
/// 64x64pt, minimumFrameInterval 1/60, queueDepth 3, BGRA.
///
/// Só 1 sessão por vez — mesmo padrão de controller único que
/// QuickDropPanelController/SpotlightPanelController já usam.
@MainActor
final class EyedropperController: NSObject {
    static let shared = EyedropperController()
    private override init() { super.init() }

    static let systemSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    static func isAuthorized() -> Bool { CGPreflightScreenCaptureAccess() }

    /// Mostra o prompt do sistema só na 1ª vez — uma vez negado, o macOS
    /// não pede de novo por esta chamada (restrição do próprio TCC, não
    /// bug daqui). Bloqueia a thread chamadora enquanto o diálogo do
    /// sistema está na tela, como qualquer outro prompt de permissão —
    /// esperado, não é pra "resolver".
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    private(set) var isActive = false

    private var overlayPanels: [EyedropperOverlayPanel] = []
    private var loupePanel: EyedropperLoupePanel?
    private var eventMonitor: Any?
    private var stream: SCStream?
    private var currentScreen: NSScreen?
    private var lastSourceRectOrigin: CGPoint?
    private var lastSampledColor: NSColor?
    private let ciContext = CIContext()

    private var onPick: ((NSColor) -> Void)?
    private var onCancel: (() -> Void)?

    /// Chama `onPick` uma vez com a cor amostrada e desmonta tudo sozinho
    /// — nunca chamar `cancel()` depois de um pick. Esc (ou `cancel()`
    /// programático) chama `onCancel` com a mesma desmontagem. Chamar
    /// `start` com uma sessão já ativa não faz nada.
    func start(onPick: @escaping (NSColor) -> Void, onCancel: @escaping () -> Void) {
        guard !isActive, Self.isAuthorized() else { return }
        isActive = true
        self.onPick = onPick
        self.onCancel = onCancel

        NSApp.activate()
        NSCursor.crosshair.set()

        overlayPanels = NSScreen.screens.map { EyedropperOverlayPanel(screen: $0) }
        overlayPanels.forEach { $0.orderFrontRegardless() }
        overlayPanels.first?.makeKey()

        let loupePanel = EyedropperLoupePanel()
        self.loupePanel = loupePanel
        loupePanel.orderFrontRegardless()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
                self.cancel()
                return nil
            }
            if event.type == .leftMouseDown {
                self.pick()
                return nil
            }
            return event
        }

        Task { await startStream(for: NSEvent.mouseLocation) }
    }

    /// Mesma desmontagem do Esc. Seguro chamar sem sessão nenhuma ativa.
    func cancel() {
        guard isActive else { return }
        let handler = onCancel
        teardown()
        handler?()
    }

    private func pick() {
        guard isActive, let color = lastSampledColor else { cancel(); return }
        let handler = onPick
        teardown()
        handler?(color)
    }

    private func teardown() {
        isActive = false
        onPick = nil
        onCancel = nil
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        overlayPanels.forEach { $0.orderOut(nil) }
        overlayPanels = []
        loupePanel?.orderOut(nil)
        loupePanel = nil
        stream?.stopCapture(completionHandler: { _ in })
        stream = nil
        currentScreen = nil
        lastSourceRectOrigin = nil
        lastSampledColor = nil
        NSCursor.arrow.set()
    }

    // MARK: - Captura

    private func startStream(for mouseLocation: NSPoint) async {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main else { return }
        await switchStream(to: screen, mouseLocation: mouseLocation)
    }

    /// Cruzar de tela = parar o stream atual e criar um novo filtrado pro
    /// display novo — SCStream é amarrado a 1 SCContentFilter/display na
    /// criação, não dá pra trocar num stream vivo.
    private func switchStream(to screen: NSScreen, mouseLocation: NSPoint) async {
        guard isActive, let displayID = Self.cgDisplayID(for: screen) else { return }
        guard let content = try? await SCShareableContent.current,
              let scDisplay = content.displays.first(where: { $0.displayID == displayID })
        else { return }

        stream?.stopCapture(completionHandler: { _ in })

        let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
        let configuration = makeConfiguration(screen: screen, mouseLocation: mouseLocation)

        let newStream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try? newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try? await newStream.startCapture()

        stream = newStream
        currentScreen = screen
    }

    private func makeConfiguration(screen: NSScreen, mouseLocation: NSPoint) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        let scale = screen.backingScaleFactor
        let center = Self.displayLocalPoint(mouseLocation: mouseLocation, on: screen)
        let sourceRect = CGRect(x: center.x - 32, y: center.y - 32, width: 64, height: 64)
        configuration.sourceRect = sourceRect
        // Pixels de saída, não pontos — sem escalar por backingScaleFactor
        // o buffer sai sub-amostrado numa tela Retina e a cor lida no
        // centro deixa de ser o pixel físico exato sob o cursor.
        configuration.width = Int(64 * scale)
        configuration.height = Int(64 * scale)
        lastSourceRectOrigin = sourceRect.origin
        return configuration
    }

    /// Cursor global (AppKit, origem inferior-esquerda, Y pra cima) -> o
    /// espaço que `sourceRect` espera (convenção CoreGraphics/SCDisplay:
    /// origem superior-esquerda, Y pra baixo). ⚠️ Ver feature-spec 'Ponto
    /// de maior risco' — não verificado contra cursor em movimento.
    private static func displayLocalPoint(mouseLocation: NSPoint, on screen: NSScreen) -> CGPoint {
        let frame = screen.frame
        let x = mouseLocation.x - frame.origin.x
        let y = frame.height - (mouseLocation.y - frame.origin.y)
        return CGPoint(x: x, y: y)
    }

    private static func cgDisplayID(for screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

extension EyedropperController: SCStreamOutput {
    /// `sampleHandlerQueue: .main` na criação do stream torna esse
    /// `assumeIsolated` válido — mesmo padrão que `observeResignKey` de
    /// QuickDropPanel.swift/SpotlightPanel.swift já usa pra callback de
    /// framework que roda em `.main` mas não é estaticamente MainActor.
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        MainActor.assumeIsolated {
            self.handleFrame(pixelBuffer)
        }
    }

    @MainActor
    private func handleFrame(_ pixelBuffer: CVPixelBuffer) {
        guard isActive else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let offset = (height / 2) * bytesPerRow + (width / 2) * 4
        let p = base.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
        // BGRA — ordem medida e confirmada no teste de captura única.
        let color = NSColor(red: CGFloat(p[2]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[0]) / 255, alpha: 1)
        lastSampledColor = color

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        loupePanel?.update(cgImage: cgImage, color: color, at: NSEvent.mouseLocation)

        followCursor()
    }

    /// Roda a cada frame (~50x/s): recentraliza o sourceRect se o cursor se
    /// moveu dentro da mesma tela, ou troca de stream se cruzou pra outra.
    /// `updateConfiguration` só é chamado quando a origem muda de verdade
    /// (cursor parado não reconfigura o stream à toa).
    private func followCursor() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = currentScreen, screen.frame.contains(mouseLocation) else {
            if let target = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                Task { await switchStream(to: target, mouseLocation: mouseLocation) }
            }
            return
        }
        let center = Self.displayLocalPoint(mouseLocation: mouseLocation, on: screen)
        let newOrigin = CGPoint(x: center.x - 32, y: center.y - 32)
        guard newOrigin != lastSourceRectOrigin, let stream else { return }
        stream.updateConfiguration(makeConfiguration(screen: screen, mouseLocation: mouseLocation), completionHandler: { _ in })
    }
}

extension EyedropperController: SCStreamDelegate {
    /// Pode chegar em qualquer queue — `Task { @MainActor }`, não
    /// `assumeIsolated`, ao contrário do output de frame acima.
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.isActive else { return }
            self.cancel()
        }
    }
}

/// Transparente, clicável, cobre 1 tela inteira — 1 por `NSScreen`, pra
/// todo pixel de toda tela ter uma janela nossa capaz de receber o clique
/// de escolha e manter alguma janela do app "key" não importa em qual tela
/// o cursor está. Não desenha nada (`isOpaque = false`,
/// `backgroundColor = .clear`) — uma janela totalmente transparente não
/// contribui pixel nenhum ao framebuffer composto, então nunca aparece na
/// própria captura nem tapa visualmente o que está por baixo.
final class EyedropperOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver   // acima de tudo, inclusive janelas de outros apps
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ignoresMouseEvents = false
        setFrame(screen.frame, display: false)
    }
}

/// A única coisa visível — um painel pequeno que segue o cursor com a
/// grade de pixels ampliada (sem interpolação — precisão de pixel é o
/// ponto da ferramenta) e o hex. `ignoresMouseEvents = true` pra nunca
/// roubar o clique de escolha, mesmo se visualmente sobrepuser o cursor
/// perto de uma borda de tela — o clique sempre alcança o
/// `EyedropperOverlayPanel` por baixo.
final class EyedropperLoupePanel: NSPanel {
    private static let size = NSSize(width: 200, height: 150)
    /// Distância do cursor até o painel — maior que a metade do sourceRect
    /// (32pt) mais margem, pra nunca sobrepor a região amostrada nem perto
    /// de borda de tela. Mais simples que excluir esta janela do
    /// `SCContentFilter` (exigiria correlacionar este `NSWindow` com um
    /// `SCWindow` via `SCShareableContent`, mais uma chamada).
    private static let cursorOffset: CGFloat = 48

    private let imageView = NSImageView()
    private let hexLabel = NSTextField(labelWithString: "")

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.85)
        hasShadow = true
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        imageView.imageScaling = .scaleProportionallyUpOrDown
        hexLabel.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        hexLabel.textColor = .white
        hexLabel.alignment = .center

        let stack = NSStackView(views: [imageView, hexLabel])
        stack.orientation = .vertical
        stack.frame = NSRect(origin: .zero, size: Self.size)
        contentView = stack
    }

    func update(cgImage: CGImage?, color: NSColor, at mouseLocation: NSPoint) {
        if let cgImage {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: 120, height: 120))
            // Ampliação com bordas de pixel nítidas — interpolação suave
            // borraria exatamente o detalhe que a ferramenta existe pra
            // mostrar.
            imageView.image = image
            imageView.layer?.magnificationFilter = .nearest
        }
        hexLabel.stringValue = Self.hex(for: color)
        setFrameOrigin(NSPoint(x: mouseLocation.x + Self.cursorOffset, y: mouseLocation.y + Self.cursorOffset))
    }

    private static func hex(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
}
```

`hex(for:)` duplica um pedacinho do que `PickColorView.rows(for:)` já faz
(rodada anterior) — DE PROPÓSITO: a lupa precisa de um preview
independente do estado SwiftUI de `PickColorView`, e puxar aquele código
pra cá criaria uma dependência reversa (`Eyedropper.swift` importando de
`NativeToolView.swift`). O painel de resultado completo (hex/RGB/HSL +
copiar) continua só em `PickColorView`, intocado.

---

## Slice B — Wren — detalhado

### 1. `Sources/Nimbus/NativeToolView.swift` — edit (`PickColorView`)

`pickedColor`/`rows(for:)`/`hslString`/o painel de resultado (SwatchView +
KeyValueTable) **ficam exatamente como estão**. Muda só o topo (novo
`@State`) e a área de ação (era 1 botão, vira o bloco de permissão + 2
botões):

```swift
private struct PickColorView: View {
    let tool: NimbusTool
    let isSidebarVisible: Bool

    @State private var pickedColor: NSColor?
    @State private var isAuthorized = EyedropperController.isAuthorized()
    @State private var isPicking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tool.name)
                    .font(.title.bold())
                Text(tool.summary)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, isSidebarVisible ? 0 : 52)

            if let pickedColor {
                VStack(alignment: .leading, spacing: 16) {
                    SwatchView(color: Color(nsColor: pickedColor), size: 72)
                    KeyValueTable(rows: rows(for: pickedColor), valuesAreMonospaced: true, showsCopy: true)
                }
            } else {
                Text("Pick a color from anywhere on screen.")
                    .foregroundStyle(.secondary)
            }

            actions
        }
        .frame(maxWidth: 460, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .onAppear {
            // Cobre o caminho "usuário concedeu em System Settings e
            // voltou pro Nimbus" — reconfere sem exigir clique nenhum.
            isAuthorized = EyedropperController.isAuthorized()
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isAuthorized {
            VStack(alignment: .leading, spacing: 10) {
                Button(isPicking ? "Picking…" : "Pick a Color (Live)") { startLivePick() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPicking)
                Button("Use System Picker") { startSystemPick() }
                    .buttonStyle(.link)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Grant Screen Recording access for a live eyedropper that previews color as you move the cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Grant Access") { requestAccess() }
                    Button("Open System Settings") { NSWorkspace.shared.open(EyedropperController.systemSettingsURL) }
                        .buttonStyle(.link)
                }
                Button("Use System Picker") { startSystemPick() }
                    .buttonStyle(.link)
            }
        }
    }

    private func startLivePick() {
        isPicking = true
        EyedropperController.shared.start(
            onPick: { color in pickedColor = color; isPicking = false },
            onCancel: { isPicking = false }
        )
    }

    /// Fallback sem permissão nenhuma — era o corpo do botão único da
    /// rodada anterior, só renomeado.
    private func startSystemPick() {
        NSColorSampler().show { color in
            guard let color else { return }
            pickedColor = color
        }
    }

    private func requestAccess() {
        _ = EyedropperController.requestAccess()
        // Pode continuar false pro processo já rodando mesmo após conceder
        // — ver feature-spec 'Nota de ambiente'. Reconferido de novo no
        // .onAppear se o usuário sair e voltar.
        isAuthorized = EyedropperController.isAuthorized()
    }

    // rows(for:)/hslString(...) — INALTERADOS, mesmo código de antes.
}
```

### 2. `Sources/Nimbus/Info.plist` — edit

Adicionar antes do `</dict>` final:

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>Nimbus uses screen recording access to power the Pick Color eyedropper, which previews colors live as you move the cursor.</string>
```

---

## Done criteria

Aplica pros 2: `swift build` limpo E `xcodebuild -project Nimbus.xcodeproj
-scheme Nimbus -configuration Debug -destination 'platform=macOS' build`
limpo. Nenhum relato pode dizer "testado ao vivo" sem medição real —
nesta rodada isso cobre especificamente: lupa acompanhando o cursor,
precisão do pixel amostrado, cruzar de monitor, e o prompt de permissão
aparecendo de verdade — NENHUM dos 4 é verificável sem GUI.

**Slice A (Rivet):**
- `Eyedropper.swift` registrado nas 2 entradas do `.pbxproj` — conferir
  com `xcodebuild`, não só `swift build`.
- Leitura de código confirma: `teardown()` é o único lugar que derruba
  stream/painéis/monitor, chamado a partir de `cancel()`, `pick()` E
  `didStopWithError` — nenhum caminho de saída deixa alguma dessas 3
  coisas viva.
- `displayLocalPoint`/`makeConfiguration` sinalizados no código como não
  verificados contra cursor em movimento (comentário `⚠️` presente) — não
  apagar essa marcação até alguém confirmar rodando de verdade.
- Nenhuma chamada a `SCShareableContent`/`SCStream` acontece antes de
  `Self.isAuthorized()` ser checado em `start()`.

**Slice B (Wren):**
- `PickColorView`: `rows(for:)`/`hslString`/o painel de resultado batem
  byte a byte com o que já existia antes desta rodada (diff não deveria
  tocar essas funções).
- `Info.plist` tem `NSScreenCaptureUsageDescription`; `plutil -lint` OK.
- Os 2 estados de `actions` (autorizado/não autorizado) cobertos, e o
  botão "Use System Picker" aparece nos dois (nunca escondido atrás da
  permissão).

Sem sidecar `.mjs` tocado, sem mudança em `UsageQuota.swift`/
`ToolCatalog.swift`/`MainWindowView.swift` — essa rodada é só o motor de
captura + a integração no Pick Color existente.
