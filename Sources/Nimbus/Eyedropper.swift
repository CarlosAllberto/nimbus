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

    /// Used by the global Pick Color shortcut to format the clipboard
    /// contents after a pick.
    static func hexString(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }

    /// Mostra o prompt do sistema só na 1ª vez — uma vez negado, o macOS
    /// não pede de novo por esta chamada (restrição do próprio TCC, não
    /// bug daqui). Bloqueia a thread chamadora enquanto o diálogo do
    /// sistema está na tela, como qualquer outro prompt de permissão —
    /// esperado, não é pra "resolver".
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    private(set) var isActive = false

    /// Screen pixels across the loupe. Odd so the centre is a single pixel —
    /// the one whose colour is reported and picked.
    static let capturedPixels = 15

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

        // The pointer is hidden while picking: the loupe sits on the cursor, so
        // the arrow would cover the very pixels being read, and the target
        // square is the pointer now. Balanced by `unhide` in `teardown`, which
        // every exit path goes through.
        NSCursor.hide()

        // No `NSApp.activate()`: like `QuickDropPanel`, the overlay is a
        // `.nonactivatingPanel` — `makeKey()` alone gives it Escape/click
        // without activating Nimbus, so a main window that happens to be
        // open never gets raised on top of the overlay.
        overlayPanels = NSScreen.screens.map { EyedropperOverlayPanel(screen: $0) }
        overlayPanels.forEach { $0.orderFrontRegardless() }
        overlayPanels.first?.makeKey()

        let loupePanel = EyedropperLoupePanel()
        // Position under the cursor before showing it, so it never flashes
        // at its default bottom-left origin first.
        loupePanel.position(at: NSEvent.mouseLocation)
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
        NSCursor.unhide()
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

        // Our own overlay and loupe are excluded from the capture. Without
        // this the loupe cannot sit on the cursor: it would film itself and
        // sample its own magnified pixels instead of the screen.
        let ownWindowIDs = Set(([loupePanel?.windowNumber] + overlayPanels.map { $0.windowNumber })
            .compactMap { $0 }
            .map { CGWindowID($0) })
        let ownWindows = content.windows.filter { ownWindowIDs.contains($0.windowID) }
        let filter = SCContentFilter(display: scDisplay, excludingWindows: ownWindows)
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
        // Without this the pointer is drawn into the captured buffer, and the
        // centre pixel the colour is read from is the pointer itself rather
        // than the screen under it — measured: over a pink target the loupe
        // reported #373737, the grey of the arrow.
        configuration.showsCursor = false

        // The region has to be small for the loupe to actually magnify. At the
        // previous 64x64 points the circle showed roughly one screen pixel per
        // point — a 1:1 copy, where no individual pixel can be told apart. An
        // odd count keeps one exact centre pixel, which is the one picked.
        let scale = screen.backingScaleFactor
        let center = Self.displayLocalPoint(mouseLocation: mouseLocation, on: screen)
        let sidePoints = CGFloat(Self.capturedPixels) / scale
        let sourceRect = CGRect(
            x: center.x - sidePoints / 2,
            y: center.y - sidePoints / 2,
            width: sidePoints,
            height: sidePoints
        )
        configuration.sourceRect = sourceRect
        // Pixels de saída, não pontos — sem escalar por backingScaleFactor
        // o buffer sai sub-amostrado numa tela Retina e a cor lida no
        // centro deixa de ser o pixel físico exato sob o cursor.
        configuration.width = Self.capturedPixels
        configuration.height = Self.capturedPixels
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
        // `CVPixelBuffer` isn't `Sendable`; under Swift 6 strict checking,
        // handing it into the `assumeIsolated` closure below is flagged as a
        // data-race risk even though this callback runs synchronously on
        // `.main` (same queue the stream was created with) and never
        // actually crosses threads. `nonisolated(unsafe)` here just tells
        // the compiler what's already true at runtime.
        nonisolated(unsafe) let buffer = pixelBuffer
        MainActor.assumeIsolated {
            self.handleFrame(buffer)
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
        let sidePoints = CGFloat(Self.capturedPixels) / screen.backingScaleFactor
        let newOrigin = CGPoint(x: center.x - sidePoints / 2, y: center.y - sidePoints / 2)
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
    private static let diameter: CGFloat = 132
    private static let pillHeight: CGFloat = 24
    /// Gap between the lens circle and the pill below it, so the two read as
    /// separate shapes instead of one fused blob.
    private static let pillGap: CGFloat = 8
    private static let labelHeight: CGFloat = pillHeight + pillGap
    private static let size = NSSize(width: diameter, height: diameter + labelHeight)

    /// A plain layer rather than an `NSImageView`: the view re-samples the
    /// image with smooth interpolation, which blurs away the pixel edges this
    /// tool exists to show. A layer honours `.nearest` magnification.
    private let imageLayer = CALayer()
    private let hexLabel = NSTextField(labelWithString: "")
    private let ring = CAShapeLayer()
    private let pill = CALayer()
    /// Outlines the one pixel that will be picked. Without it the loupe shows
    /// a magnified patch with no way to tell which pixel it is reporting.
    private let target = CAShapeLayer()
    private let grid = CAShapeLayer()

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        // Transparent: only the circle and the label should be visible. A panel
        // background would put a black rectangle over the screen the tool exists
        // to look at.
        backgroundColor = .clear
        // No panel shadow: it drew a dark halo around the lens that read as a
        // border and muddied the colours right next to the sampled pixel.
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let container = NSView(frame: NSRect(origin: .zero, size: Self.size))
        container.wantsLayer = true

        // Circular, like the system sampler: a square of magnified pixels reads
        // as a screenshot sitting on the screen rather than as a lens.
        let circleFrame = NSRect(x: 0, y: Self.labelHeight, width: Self.diameter, height: Self.diameter)
        imageLayer.frame = circleFrame
        imageLayer.magnificationFilter = .nearest
        imageLayer.contentsGravity = .resize
        imageLayer.cornerRadius = Self.diameter / 2
        imageLayer.masksToBounds = true

        ring.path = CGPath(ellipseIn: circleFrame.insetBy(dx: 1, dy: 1), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = NSColor.white.cgColor
        ring.lineWidth = 2

        // The pill's own background carries the sampled colour — no separate
        // swatch needed. Corners are lightly rounded rather than fully
        // pill-shaped, so it reads as a small chip rather than a capsule. The
        // border echoes the lens ring, thinner so the ring stays the primary
        // shape.
        let pillWidth: CGFloat = 84
        pill.frame = NSRect(x: (Self.diameter - pillWidth) / 2, y: 0, width: pillWidth, height: Self.pillHeight)
        pill.cornerRadius = 6
        pill.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        pill.borderWidth = 1

        // Nudged 1pt below true centre: the hex string has no descenders, so
        // centring on the full line height (which reserves descender space)
        // reads as too much padding underneath the digits.
        hexLabel.frame = NSRect(x: pill.frame.minX, y: 2, width: pillWidth, height: 18)
        hexLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        hexLabel.alignment = .center

        // One magnified pixel, in points.
        let pixelSide = Self.diameter / CGFloat(EyedropperController.capturedPixels)

        // A faint grid so the pixels read as pixels and can be counted out from
        // the centre; it stays under the target square.
        let gridPath = CGMutablePath()
        for step in 0...EyedropperController.capturedPixels {
            let offset = CGFloat(step) * pixelSide
            gridPath.move(to: CGPoint(x: offset, y: Self.labelHeight))
            gridPath.addLine(to: CGPoint(x: offset, y: Self.labelHeight + Self.diameter))
            gridPath.move(to: CGPoint(x: 0, y: Self.labelHeight + offset))
            gridPath.addLine(to: CGPoint(x: Self.diameter, y: Self.labelHeight + offset))
        }
        grid.path = gridPath
        grid.strokeColor = NSColor.white.withAlphaComponent(0.16).cgColor
        grid.lineWidth = 0.5
        grid.fillColor = NSColor.clear.cgColor
        // Clipped to the circle so the grid doesn't spill outside the lens.
        let circleMask = CAShapeLayer()
        circleMask.path = CGPath(ellipseIn: circleFrame, transform: nil)
        grid.mask = circleMask

        let centreOrigin = (Self.diameter - pixelSide) / 2
        target.path = CGPath(rect: CGRect(
            x: centreOrigin,
            y: Self.labelHeight + centreOrigin,
            width: pixelSide,
            height: pixelSide
        ), transform: nil)
        target.fillColor = NSColor.clear.cgColor
        target.strokeColor = NSColor.white.cgColor
        target.lineWidth = 1.5
        // A dark outer stroke keeps the white square visible over light colours.
        target.shadowColor = NSColor.black.cgColor
        target.shadowOpacity = 0.9
        target.shadowRadius = 1
        target.shadowOffset = .zero

        // All layers, in draw order. A subview would sit above sibling layers
        // and hide the grid and the target square underneath it.
        container.layer?.addSublayer(imageLayer)
        container.layer?.addSublayer(grid)
        container.layer?.addSublayer(target)
        container.layer?.addSublayer(ring)
        container.layer?.addSublayer(pill)
        container.addSubview(hexLabel)
        contentView = container
    }

    func update(cgImage: CGImage?, color: NSColor, at mouseLocation: NSPoint) {
        if let cgImage {
            // No implicit animation: the contents change every frame, and a
            // cross-fade between them is exactly the blur to avoid.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageLayer.contents = cgImage
            CATransaction.commit()
        }
        hexLabel.stringValue = Self.hex(for: color)
        hexLabel.textColor = Self.readableTextColor(on: color)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.backgroundColor = color.cgColor
        CATransaction.commit()
        position(at: mouseLocation)
    }

    /// Moves the panel so the lens is centred on `mouseLocation`, independent
    /// of `update`. Called once right after init, before the panel is first
    /// ordered front — otherwise it briefly shows at its `contentRect`
    /// origin (screen bottom-left) until the first captured frame arrives.
    func position(at mouseLocation: NSPoint) {
        // The circle is centred on the cursor — not the panel, whose label sits
        // below the circle and would pull it off-centre.
        setFrameOrigin(NSPoint(
            x: mouseLocation.x - Self.diameter / 2,
            y: mouseLocation.y - Self.labelHeight - Self.diameter / 2
        ))
    }

    private static func hex(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }

    /// With the pill's background now the sampled colour itself, a fixed
    /// white label would vanish over light samples — pick black or white by
    /// the background's relative luminance instead.
    private static func readableTextColor(on background: NSColor) -> NSColor {
        let rgb = background.usingColorSpace(.deviceRGB) ?? background
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance > 0.6 ? .black : .white
    }
}
