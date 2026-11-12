import AppKit

final class TestDisplays: DisplayServicing {
    var available = true
    var externalOnline = true
    var externalPresent = true
    var builtinActive = true
    var failDisconnect = false
    var operations: [Bool] = []
    func devices() throws -> [DisplayDevice] {
        let builtin = DisplayDevice(id: "builtin", displayID: 1, name: "Built-in", builtIn: true, online: true, active: builtinActive)
        guard externalPresent else { return [builtin] }
        return [builtin, DisplayDevice(id: "external", displayID: 2, name: "Test display", builtIn: false, online: externalOnline, active: externalOnline)]
    }
    func setEnabled(_ identity: String, enabled: Bool) throws {
        precondition(identity == "external", "Never change the built-in display")
        operations.append(enabled)
        if !enabled && failDisconnect { throw DisplayFailure("Simulated failure") }
        externalOnline = enabled
    }
}

@main
struct ControllerTests {
    @MainActor static func main() async throws {
        let hardware = TestDisplays()
        let controller = DisplayController(bridge: hardware, startsMonitoring: false, transitionDelay: 0)
        var announced: [String] = []
        var cleared: [String] = []
        controller.onAutomaticallyPaused = { announced.append($0.id) }
        controller.onReconnected = { cleared.append($0) }

        await controller.toggle(controller.external[0])
        precondition(!hardware.externalOnline && controller.held.contains("external"))
        precondition(announced.isEmpty, "Manual pause must not announce a new plug-in")

        // Unplug and replug a paused display; auto-pause must confirm offline before notifying.
        hardware.externalPresent = false
        await controller.reconcile()
        precondition(announced.isEmpty && controller.held.contains("external"))
        hardware.externalPresent = true
        hardware.externalOnline = true
        await controller.reconcile()
        precondition(!hardware.externalOnline && announced == ["external"])
        precondition(controller.pausedNotice?.id == "external")
        await controller.reconcile()
        precondition(announced.count == 1, "A stable disconnected monitor must not spam notifications")

        let restored = await controller.reconnect("external")
        precondition(restored && hardware.externalOnline && controller.held.isEmpty)
        precondition(controller.pausedNotice == nil && cleared == ["external"])
        let staleAction = await controller.reconnect("external")
        precondition(staleAction && hardware.externalOnline, "An old notification must never toggle a display off")
        precondition(hardware.operations.suffix(2).allSatisfy { $0 })

        // Real docking can leave a disabled display offline throughout insertion.
        // In that case the hardware event, not an online transition, must show the popup.
        await controller.toggle(controller.external[0])
        let operationsBeforePhysicalInsertion = hardware.operations.count
        await controller.physicalDisplayConnected()
        precondition(!hardware.externalOnline && announced.count == 2)
        precondition(hardware.operations.count == operationsBeforePhysicalInsertion,
                     "An already paused display needs a notice, not another disable transaction")
        _ = await controller.reconnect("external")
        await controller.physicalDisplayConnected()
        precondition(hardware.externalOnline && announced.count == 2,
                     "An unpaused display must not produce a paused notification")

        // No success notification if macOS refuses to disconnect after reconnection.
        await controller.toggle(controller.external[0])
        hardware.externalOnline = true
        hardware.failDisconnect = true
        await controller.reconcile()
        precondition(announced.count == 2 && controller.error != nil)

        // A physically missing display cannot be reconnected by an obsolete notification.
        hardware.externalPresent = false
        let missing = await controller.reconnect("external")
        precondition(!missing && controller.error != nil)
        print("PASS: replug notification, no duplicates, explicit/stale reconnect, failure and missing-display recovery")
    }
}
