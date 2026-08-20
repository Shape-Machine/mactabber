import AppKit
import ApplicationServices
import CoreGraphics
import ServiceManagement

private let appDelegate = AppDelegate()
private let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = appDelegate
app.run()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var switcher: AppSwitcher!
    private var keyMonitor: CommandTabMonitor!

    func applicationDidFinishLaunching(_ notification: Notification) {
        switcher = AppSwitcher()
        keyMonitor = CommandTabMonitor(switcher: switcher)
        configureMenu()
        configureLoginItem()
        requestAccessibilityAndStart()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "MacTabber")

        let menu = NSMenu()
        let state = NSMenuItem(title: "Command–Tab: starting…", action: nil, keyEquivalent: "")
        state.tag = 1
        menu.addItem(state)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open Accessibility Settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        menu.addItem(withTitle: "Start at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        menu.items.last?.tag = 2
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit MacTabber", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        refreshMenu()
    }

    private func requestAccessibilityAndStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        tryStartMonitor()

        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.tryStartMonitor()
        }
    }

    private func tryStartMonitor() {
        if AXIsProcessTrusted(), !keyMonitor.isRunning {
            keyMonitor.start()
        }
        refreshMenu()
    }

    private func configureLoginItem() {
        guard SMAppService.mainApp.status == .notRegistered else { return }
        try? SMAppService.mainApp.register()
    }

    private func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.item(withTag: 1)?.title = keyMonitor?.isRunning == true
            ? "Command–Tab: active"
            : "Command–Tab: Accessibility permission needed"
        let login = menu.item(withTag: 2)
        login?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t update the login item"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshMenu()
    }
}

final class CommandTabMonitor {
    private let switcher: AppSwitcher
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isRunning = false

    init(switcher: AppSwitcher) { self.switcher = switcher }

    func start() {
        guard !isRunning else { return }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<CommandTabMonitor>.fromOpaque(context).takeUnretainedValue()
                    .handle(type: type, event: event)
            },
            userInfo: context
        ) else { return }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown, keyCode == 48, flags.contains(.maskCommand) {
            DispatchQueue.main.async { [switcher] in
                switcher.advance(backward: flags.contains(.maskShift))
            }
            return nil
        }

        if type == .keyDown, keyCode == 53, switcher.isVisible {
            DispatchQueue.main.async { [switcher] in switcher.cancel() }
            return nil
        }

        if type == .flagsChanged, !flags.contains(.maskCommand), switcher.isVisible {
            DispatchQueue.main.async { [switcher] in switcher.commit() }
        }
        return Unmanaged.passUnretained(event)
    }
}

struct SwitcherApp {
    let application: NSRunningApplication
    let name: String
    let icon: NSImage
}

final class AppSwitcher {
    private let panel: NSPanel
    private let stack = NSStackView()
    private var apps: [SwitcherApp] = []
    private var selectedIndex = 0
    private var rows: [SwitcherRow] = []
    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        panel.contentView = effect

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        effect.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])
    }

    func advance(backward: Bool) {
        if !isVisible {
            apps = CurrentDesktop.apps()
            guard !apps.isEmpty else { return }
            selectedIndex = apps.count > 1 ? (backward ? apps.count - 1 : 1) : 0
            rebuildRows()
            show()
        } else {
            let delta = backward ? -1 : 1
            selectedIndex = (selectedIndex + delta + apps.count) % apps.count
            updateSelection()
        }
    }

    func commit() {
        guard apps.indices.contains(selectedIndex) else { cancel(); return }
        let selected = apps[selectedIndex].application
        panel.orderOut(nil)
        selected.activate(options: [])
        reset()
    }

    func cancel() {
        panel.orderOut(nil)
        reset()
    }

    private func reset() {
        apps = []
        rows = []
    }

    private func rebuildRows() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rows = apps.map { app in
            let row = SwitcherRow(app: app)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalToConstant: 300).isActive = true
            row.heightAnchor.constraint(equalToConstant: 48).isActive = true
            return row
        }
        updateSelection()
        panel.setContentSize(NSSize(width: 324, height: CGFloat(apps.count * 52 + 24)))
    }

    private func updateSelection() {
        for (index, row) in rows.enumerated() { row.isSelected = index == selectedIndex }
    }

    private func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        var origin = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.midY - panel.frame.height / 2)
        origin.y = max(frame.minY + 20, origin.y)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }
}

final class SwitcherRow: NSView {
    var isSelected = false { didSet { needsDisplay = true } }

    init(app: SwitcherApp) {
        super.init(frame: .zero)
        wantsLayer = true

        let image = NSImageView(image: app.icon)
        image.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: app.name)
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        addSubview(image)
        addSubview(label)
        image.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 34),
            image.heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            NSColor.controlAccentColor.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        }
        super.draw(dirtyRect)
    }
}

enum CurrentDesktop {
    static func apps() -> [SwitcherApp] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[CFString: Any]] else { return [] }

        var seen = Set<pid_t>()
        var result: [SwitcherApp] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for window in info {
            guard let pidNumber = window[kCGWindowOwnerPID] as? NSNumber,
                  let layer = window[kCGWindowLayer] as? NSNumber,
                  layer.intValue == 0 else { continue }
            let pid = pidNumber.int32Value
            guard pid != ownPID, !seen.contains(pid),
                  let running = NSRunningApplication(processIdentifier: pid),
                  running.activationPolicy == .regular,
                  !running.isTerminated else { continue }

            let name = running.localizedName
                ?? (window[kCGWindowOwnerName] as? String)
                ?? "Application"
            let icon = running.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
            seen.insert(pid)
            result.append(SwitcherApp(application: running, name: name, icon: icon))
        }

        // Quartz returns windows front-to-back, matching the expected switcher order.
        return result
    }
}
