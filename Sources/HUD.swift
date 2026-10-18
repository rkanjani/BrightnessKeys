import AppKit

/// A small brightness overlay shown on the display being adjusted.
final class BrightnessHUD {
    private let panel: NSPanel
    private let icon = NSImageView()
    private let bar = LevelBar()
    private var hideWork: DispatchWorkItem?

    private let size = NSSize(width: 240, height: 44)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.blendingMode = .behindWindow
        background.wantsLayer = true
        background.layer?.cornerRadius = size.height / 2
        background.layer?.masksToBounds = true

        icon.frame = NSRect(x: 14, y: 11, width: 22, height: 22)
        icon.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        icon.contentTintColor = .labelColor
        bar.frame = NSRect(x: 46, y: 18, width: size.width - 46 - 20, height: 8)

        background.addSubview(icon)
        background.addSubview(bar)
        panel.contentView = background
    }

    func show(_ value: Double, on displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: {
            $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID
        }) else { return }

        let symbol = value < 0.01 ? "sun.min" : value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Brightness")
        bar.level = value

        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12))
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                self?.panel.animator().alphaValue = 0
            }, completionHandler: { self?.panel.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

private final class LevelBar: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        let width = max(bounds.height, bounds.width * CGFloat(min(max(level, 0), 1)))
        if level > 0 {
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height),
                         xRadius: radius, yRadius: radius).fill()
        }
    }
}
