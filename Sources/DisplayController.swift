import AppKit
import CoreGraphics
import Combine
import Darwin

struct DisplayDevice: Identifiable {
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    let builtIn: Bool
    let online: Bool
    let active: Bool
}

struct DisplayFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

protocol DisplayServicing {
    var available: Bool { get }
    func devices() throws -> [DisplayDevice]
    func setEnabled(_ identity: String, enabled: Bool) throws
}

// Private API is isolated here and resolved at runtime, never linked directly.
final class DisplayBridge: DisplayServicing {
    private struct KnownDisplay: Codable, Equatable {
        let identity: String
        let vendor: UInt32
        let model: UInt32
        let serial: UInt32
        let lastID: UInt32
        let name: String
    }
    typealias ListFunction = @convention(c) (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError
    typealias EnableFunction = @convention(c) (CGDisplayConfigRef?, UInt32, Bool) -> CGError
    private let handle: UnsafeMutableRawPointer?
    private let list: ListFunction?
    private let enable: EnableFunction?
    private let preferences = UserDefaults(suiteName: "de.christianraudzis.deextend.display-cache")!
    private var known: [KnownDisplay] = []

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        handle = library
        func symbol(_ names: [String]) -> UnsafeMutableRawPointer? {
            guard let library else { return nil }
            return names.lazy.compactMap { dlsym(library, $0) }.first
        }
        list = symbol(["SLSGetDisplayList", "CGSGetDisplayList"]).map { unsafeBitCast($0, to: ListFunction.self) }
        enable = symbol(["SLSConfigureDisplayEnabled", "CGSConfigureDisplayEnabled"]).map { unsafeBitCast($0, to: EnableFunction.self) }
        if let data = preferences.data(forKey: "knownDisplays"),
           let saved = try? JSONDecoder().decode([KnownDisplay].self, from: data) { known = saved }
    }

    var available: Bool { list != nil && enable != nil }

    func devices() throws -> [DisplayDevice] {
        guard let list else { throw DisplayFailure(L.text("error.listUnavailable")) }
        var ids = [UInt32](repeating: 0, count: 128)
        var count: UInt32 = 0
        try check(list(UInt32(ids.count), &ids, &count), L.text("operation.list"))
        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        })
        let previous = known
        let result: [DisplayDevice] = ids.prefix(Int(min(count, 128))).compactMap { display in
            // Ignore stale WindowServer entries, including after unplugging a hub.
            guard CGDisplayIsOnline(display) != 0 || CGDisplayVendorNumber(display) != 0 || CGDisplayModelNumber(display) != 0 else { return nil }
            let vendor = CGDisplayVendorNumber(display)
            let model = CGDisplayModelNumber(display)
            let serial = CGDisplaySerialNumber(display)
            let candidates = known.filter { $0.vendor == vendor && $0.model == model && $0.serial == serial }
            let cached = candidates.first { $0.lastID == display } ?? (candidates.count == 1 ? candidates.first : nil)
            let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue()
            // On macOS 27 a disabled external retains its hardware tuple, but has no UUID.
            // Only match an entry freshly enumerated by SkyLight; never send a cached ID blindly.
            guard let identity = uuid.map({ CFUUIDCreateString(nil, $0)! as String }) ?? cached?.identity else { return nil }
            let builtin = CGDisplayIsBuiltin(display) != 0
            let name = names[display] ?? cached?.name ?? (builtin ? L.text("display.builtin") : L.text("display.external"))
            if uuid != nil {
                known.removeAll { $0.identity == identity }
                known.append(KnownDisplay(identity: identity, vendor: vendor, model: model, serial: serial, lastID: display, name: name))
            }
            return DisplayDevice(id: identity, displayID: display,
                                 name: name,
                                 builtIn: builtin, online: CGDisplayIsOnline(display) != 0,
                                 active: CGDisplayIsActive(display) != 0)
        }
        if known != previous, let data = try? JSONEncoder().encode(known) {
            preferences.set(data, forKey: "knownDisplays")
            // Persist recovery identity before a subsequent configuration can remove the UUID.
            preferences.synchronize()
        }
        return result
    }

    func setEnabled(_ identity: String, enabled: Bool) throws {
        guard let enable else { throw DisplayFailure(L.text("error.enableUnavailable")) }
        // Always resolve the UUID against the current private display list before changing it.
        let current = try devices()
        guard let target = current.first(where: { $0.id == identity }), !target.builtIn else {
            throw DisplayFailure(L.text("error.unreachable"))
        }
        if target.online == enabled { return }
        if !enabled && !Self.mayDisconnect(target, among: current) {
            throw DisplayFailure(L.text("error.lidRequired"))
        }
        var config: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&config), L.text("operation.begin"))
        guard let config else { throw DisplayFailure(L.text("error.noConfiguration")) }
        var consumed = false
        defer { if !consumed { CGCancelDisplayConfiguration(config) } }
        if !enabled && CGDisplayIsInMirrorSet(target.displayID) != 0 {
            try check(CGConfigureDisplayMirrorOfDisplay(config, target.displayID, kCGNullDirectDisplay), L.text("operation.unmirror"))
        }
        try check(enable(config, target.displayID, enabled), enabled ? L.text("operation.connect") : L.text("operation.disconnect"))
        // Private display enable state does not reliably revert on app exit, even with
        // .forAppOnly. Restore explicitly on quit and keep recovery identities on disk.
        consumed = true
        try check(CGCompleteDisplayConfiguration(config, .forSession), L.text("operation.apply"))
    }

    static func mayDisconnect(_ target: DisplayDevice, among devices: [DisplayDevice]) -> Bool {
        !target.builtIn && target.online && devices.contains { $0.builtIn && $0.online && $0.active }
    }

    private func check(_ result: CGError, _ action: String) throws {
        guard result == .success else { throw DisplayFailure(L.text("error.operation", action, result.rawValue)) }
    }
}

@MainActor
final class DisplayController: ObservableObject {
    @Published var devices: [DisplayDevice] = []
    @Published var held: Set<String> = []
    @Published var busy = false
    @Published var message: String?
    @Published var error: String?
    @Published var pausedNotice: DisplayDevice?
    var onAutomaticallyPaused: ((DisplayDevice) -> Void)?
    var onReconnected: ((String) -> Void)?
    let bridge: any DisplayServicing
    private let transitionDelay: UInt64
    private var names: [String: String] = [:]
    private var timer: Timer?
    private var attempts: [String: [Date]] = [:]
    private var settlingUntil = Date.distantPast

    var external: [DisplayDevice] { devices.filter { !$0.builtIn } }
    var canDisconnect: Bool { devices.contains { $0.builtIn && $0.online && $0.active } }

    init(bridge: any DisplayServicing = DisplayBridge(), startsMonitoring: Bool = true,
         transitionDelay: UInt64 = 650_000_000) {
        self.bridge = bridge
        self.transitionDelay = transitionDelay
        refresh()
        guard startsMonitoring else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.reconcile() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func woke() { settlingUntil = Date().addingTimeInterval(5) }

    func refresh() {
        do {
            let current = try bridge.devices()
            for d in current where d.online { names[d.id] = d.name }
            devices = current.map { d in
                DisplayDevice(id: d.id, displayID: d.displayID, name: names[d.id] ?? d.name,
                              builtIn: d.builtIn, online: d.online, active: d.active)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }

    func toggle(_ device: DisplayDevice) async {
        guard !busy else { return }
        if held.contains(device.id) || !device.online {
            _ = await reconnect(device.id)
            return
        }
        busy = true
        defer { busy = false }
        error = nil
        do {
            // Record intent before disconnecting so any verification failure still has a recovery path.
            held.insert(device.id)
            try await apply(device.id, enabled: false)
            message = L.text("message.disconnected", device.name)
        } catch {
            if (try? bridge.devices().first { $0.id == device.id }?.online) == true { held.remove(device.id) }
            self.error = error.localizedDescription
        }
        refresh()
    }

    /// Notification actions must be idempotent: a stale Reconnect action never disconnects.
    @discardableResult
    func reconnect(_ identity: String) async -> Bool {
        guard !busy else { error = L.text("error.busy"); return false }
        busy = true
        defer { busy = false; refresh() }
        // The user's reconnect intent takes precedence over automatic pause, even on failure.
        held.remove(identity)
        attempts[identity] = nil
        error = nil
        do {
            guard let display = try bridge.devices().first(where: { $0.id == identity }), !display.builtIn else {
                throw DisplayFailure(L.text("error.unreachable"))
            }
            try await apply(identity, enabled: true)
            message = L.text("message.reconnected", display.name)
            if pausedNotice?.id == identity { pausedNotice = nil }
            onReconnected?(identity)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    private func apply(_ id: String, enabled: Bool) async throws {
        for attempt in 0..<3 {
            try bridge.setEnabled(id, enabled: enabled)
            try await Task.sleep(nanoseconds: transitionDelay)
            if let fresh = try bridge.devices().first(where: { $0.id == id }), fresh.online == enabled { return }
            if attempt == 2 { throw DisplayFailure(L.text("error.unconfirmed")) }
        }
    }

    func reconcile() async {
        guard !busy, Date() >= settlingUntil else { return }
        refresh()
        guard canDisconnect else {
            if !held.isEmpty {
                _ = await restoreAll()
                message = L.text("message.builtinInactive")
            }
            return
        }
        for d in external where held.contains(d.id) && d.online {
            let recent = (attempts[d.id] ?? []).filter { Date().timeIntervalSince($0) < 60 }
            guard recent.count < 3 else {
                held.remove(d.id)
                error = L.text("error.repeatedReconnect", d.name)
                continue
            }
            attempts[d.id] = recent + [Date()]
            busy = true
            do {
                try await apply(d.id, enabled: false)
                pausedNotice = d
                message = L.text("notice.body", d.name)
                onAutomaticallyPaused?(d)
            }
            catch { self.error = error.localizedDescription; held.remove(d.id) }
            busy = false
        }
        refresh()
    }

    /// Physical insertion is meaningful even when macOS keeps a paused display offline.
    func physicalDisplayConnected() async {
        // Let an in-flight transaction finish; never announce an unverified disconnect.
        for _ in 0..<20 where busy {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard !busy else { return }
        refresh()
        guard canDisconnect else { return }
        let onlineBefore = Set(external.filter { $0.online }.map(\.id))
        await reconcile()
        for display in external where held.contains(display.id) && !display.online && !onlineBefore.contains(display.id) {
            pausedNotice = display
            onAutomaticallyPaused?(display)
        }
    }

    func restoreAll() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false; refresh() }
        let targets = held
        held.removeAll()
        error = nil
        var restored = true
        for id in targets {
            do {
                // A physically unplugged monitor needs no restoration.
                if try bridge.devices().contains(where: { $0.id == id }) { try await apply(id, enabled: true) }
                onReconnected?(id)
            } catch { self.error = error.localizedDescription; restored = false; held.insert(id) }
        }
        if restored {
            pausedNotice = nil
            message = L.text("message.allRestored")
        }
        return restored
    }
}
