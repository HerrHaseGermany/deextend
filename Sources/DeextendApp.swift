import SwiftUI
import Combine

@main
struct DeextendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DisplayController()
    private lazy var notices = ConnectionNoticePresenter(controller: controller)
    private var terminating = false
    private var controlsPopover: NSPopover?
    private var statusItem: NSStatusItem?
    private var statusObservation: AnyCancellable?
    private var physicalDisplayMonitor: PhysicalDisplayMonitor?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--diagnose"),
              !CommandLine.arguments.contains("--verify-toggle") else { return }
        controller.onAutomaticallyPaused = { [weak self] display in self?.notices.announce(display) }
        controller.onReconnected = { [weak self] identity in self?.notices.clear(identity) }
        let monitor = PhysicalDisplayMonitor()
        monitor.onConnection = { [weak self] in
            Task { @MainActor [weak self] in
                // Service matching precedes some WindowServer updates after docking.
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self?.controller.physicalDisplayConnected()
            }
        }
        physicalDisplayMonitor = monitor
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusItem()
        statusObservation = controller.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
    }

    private func updateStatusItem() {
        statusItem?.button?.image = controller.held.isEmpty
            ? NSImage(systemSymbolName: "display", accessibilityDescription: "Deextend")
            : StatusImages.pausedDisplay
        statusItem?.button?.toolTip = controller.busy ? L.text("status.busy")
            : L.text("status.hint")
        statusItem?.button?.setAccessibilityLabel(controller.held.isEmpty ? L.text("status.connected") : L.text("status.paused"))
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if controlsPopover?.isShown == true { controlsPopover?.performClose(nil) }
            else { showControls() }
            return
        }
        guard !controller.busy else { return }
        Task {
            controller.refresh()
            if !controller.held.isEmpty {
                if !(await controller.restoreAll()) {
                    showControls()
                }
            } else {
                let targets = controller.external.filter { $0.online }
                guard !targets.isEmpty, controller.canDisconnect else {
                    showControls()
                    return
                }
                for target in targets {
                    await controller.toggle(target)
                    if controller.error != nil {
                        showControls()
                        break
                    }
                }
            }
        }
    }

    private func showControls() {
        guard let button = statusItem?.button else { return }
        controller.refresh()
        if controlsPopover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = NSHostingController(rootView: MonitorPanel(controller: controller))
            controlsPopover = popover
        }
        guard let popover = controlsPopover, let content = popover.contentViewController else { return }
        popover.contentSize = content.view.fittingSize
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Reopening from Finder uses the same menu anchored to the status item.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "de.christianraudzis.deextend")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            print("Deextend läuft bereits in der Menüleiste.")
            NSApp.terminate(nil)
            return
        }
        let args = CommandLine.arguments
        if args.contains("--diagnose") {
            controller.refresh()
            print("Private Display-Schnittstelle: \(controller.bridge.available ? "verfügbar" : "fehlt")")
            for d in controller.devices {
                print("\(d.name) | \(d.builtIn ? "intern" : "extern") | online=\(d.online) active=\(d.active) | \(d.id)")
            }
            NSApp.terminate(nil)
        } else if args.contains("--verify-toggle") {
            Task { await verifyToggle() }
        } else {
            installStatusItem()
        }
    }

    private func verifyToggle() async {
        guard let target = controller.external.first(where: { $0.online }), controller.canDisconnect else {
            print("FAIL: Aktives internes und externes Display erforderlich.")
            exit(1)
        }
        print("TEST: \(target.name) virtuell trennen …")
        await controller.toggle(target)
        let disconnected = controller.devices.first { $0.id == target.id }?.online == false
        print("Extern offline: \(disconnected); intern aktiv: \(controller.canDisconnect)")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let restored = await controller.restoreAll()
        let online = controller.devices.first { $0.id == target.id }?.online == true
        print("Wieder verbunden: \(online)")
        if let error = controller.error { print("Fehler: \(error)") }
        // Exit only after the explicit restoration attempt.
        exit(disconnected && restored && online ? 0 : 1)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating, !controller.held.isEmpty else { return .terminateNow }
        terminating = true
        Task {
            // A click can arrive during an in-flight display transaction.
            while controller.busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            let restored = await controller.restoreAll()
            if !restored {
                let alert = NSAlert()
                alert.messageText = L.text("error.restoreTitle")
                alert.informativeText = controller.error ?? L.text("error.replug")
                alert.addButton(withTitle: L.text("action.keepOpen"))
                alert.addButton(withTitle: L.text("action.quitAnyway"))
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    terminating = false
                    sender.reply(toApplicationShouldTerminate: false)
                    return
                }
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
