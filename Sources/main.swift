import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var displays: [CGDirectDisplayID: Display] = [:]
    private let hud = BrightnessHUD()
    private lazy var keyTap = BrightnessKeyTap { [unowned self] up, isDown, fine in
        self.handleKey(up: up, isDown: isDown, fine: fine)
    }
    /// Steps pressed while a display's brightness is still being read.
    private var pendingSteps: [CGDirectDisplayID: Int] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Brightness")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        refreshDisplays()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refreshDisplays() }
        keyTap.start(prompt: true)
    }

    private func refreshDisplays() {
        let old = displays
        displays = DisplayDiscovery.discover()
        // Keep cached brightness for displays that are still connected.
        for (id, display) in displays where old[id] == nil { display.read { _ in } }
        for (id, display) in old where displays[id] != nil { displays[id] = display }
    }

    // MARK: Keys

    private func displayUnderCursor() -> CGDirectDisplayID? {
        let point = CGEvent(source: nil)?.location ?? .zero
        var id: CGDirectDisplayID = 0
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &id, &count) == .success, count > 0 else { return nil }
        return id
    }

    /// Returns true if we handled the key (so macOS shouldn't also act on it).
    private func handleKey(up: Bool, isDown: Bool, fine: Bool) -> Bool {
        guard let id = displayUnderCursor(), let display = displays[id] else { return false }
        // On the built-in screen, let macOS do its native thing (its own HUD, auto-brightness, etc.).
        if display.isBuiltIn { return false }
        if isDown { step(display, by: up ? 1 : -1, fine: fine) }
        return true
    }

    private func step(_ display: Display, by direction: Int, fine: Bool) {
        if display.isFresh, let value = display.cached {
            apply(display, value, steps: direction, fine: fine)
            return
        }
        if pendingSteps[display.id] != nil {
            pendingSteps[display.id]! += direction
            return
        }
        pendingSteps[display.id] = direction
        display.read { [weak self] value in
            guard let self else { return }
            let steps = self.pendingSteps.removeValue(forKey: display.id) ?? 0
            self.apply(display, value ?? 0.5, steps: steps, fine: fine)
        }
    }

    private func apply(_ display: Display, _ current: Double, steps: Int, fine: Bool) {
        let divisions = fine ? 64.0 : 16.0
        let value = min(max(((current * divisions).rounded() + Double(steps)) / divisions, 0), 1)
        display.set(value)
        hud.show(value, on: display.id)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Brightness keys follow your pointer", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let sorted = displays.values.sorted { ($0.isBuiltIn ? 0 : 1, $0.name) < ($1.isBuiltIn ? 0 : 1, $1.name) }
        for display in sorted {
            let row = SliderRow(display: display)
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
            display.read { [weak row] value in row?.update(value) }
        }
        let unsupported = NSScreen.screens.count - displays.count
        if unsupported > 0 {
            let item = NSMenuItem(title: "\(unsupported) display(s) don't support DDC", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if !keyTap.isActive {
            menu.addItem(NSMenuItem(title: "Allow Accessibility Access…", action: #selector(openAccessibility), keyEquivalent: ""))
        }
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items where item.action != nil && item.target == nil && item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
    }

    @objc private func openAccessibility() {
        keyTap.start(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}

/// A menu row with the display's name and a brightness slider.
private final class SliderRow: NSView {
    private let display: Display
    private let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(display: Display) {
        self.display = display
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 48))

        let label = NSTextField(labelWithString: display.name)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 26, width: 220, height: 16)

        slider.frame = NSRect(x: 18, y: 4, width: 224, height: 20)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        if let value = display.cached { slider.doubleValue = value }

        addSubview(label)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(_ value: Double?) {
        if let value { slider.doubleValue = value }
    }

    @objc private func changed() {
        display.set(slider.doubleValue)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let args = CommandLine.arguments

/// CLI helpers for testing: `--list` and `--set <display name or id> <0-100>`.
if args.count > 1 {
    let displays = DisplayDiscovery.discover()
    func waitFor(_ body: (@escaping () -> Void) -> Void) {
        var done = false
        body { done = true }
        while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    switch args[1] {
    case "--list":
        for display in displays.values.sorted(by: { $0.id < $1.id }) {
            waitFor { finish in
                display.read { value in
                    let level = value.map { "\(Int(($0 * 100).rounded()))%" } ?? "unreadable"
                    print("\(display.id)\t\(display.kind)\t\(display.isBuiltIn ? "built-in" : "external")\t\(level)\t\(display.name)")
                    finish()
                }
            }
        }
    case "--set" where args.count == 4:
        guard let percent = Double(args[3]),
              let display = displays.values.first(where: { String($0.id) == args[2] || $0.name.localizedCaseInsensitiveContains(args[2]) })
        else { print("No matching display"); exit(1) }
        waitFor { finish in display.read { _ in finish() } }
        display.set(percent / 100)
        Thread.sleep(forTimeInterval: 0.3)
        print("Set \(display.name) to \(Int(percent))%")
    default:
        print("Usage: BrightnessKeys [--list | --set <display> <0-100>]")
    }
    exit(0)
}

let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
