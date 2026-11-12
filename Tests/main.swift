import AppKit

func display(_ id: String, builtin: Bool = false, online: Bool = true, active: Bool = true) -> DisplayDevice {
    DisplayDevice(id: id, displayID: 1, name: id, builtIn: builtin, online: online, active: active)
}
let external = display("external")
let internalDisplay = display("internal", builtin: true)
precondition(DisplayBridge.mayDisconnect(external, among: [external, internalDisplay]))
precondition(!DisplayBridge.mayDisconnect(internalDisplay, among: [external, internalDisplay]))
precondition(!DisplayBridge.mayDisconnect(external, among: [external]))
precondition(!DisplayBridge.mayDisconnect(external, among: [external, display("closed", builtin: true, active: false)]))
precondition(!DisplayBridge.mayDisconnect(external, among: [external, display("offline", builtin: true, online: false)]))
precondition(!DisplayBridge.mayDisconnect(display("off", online: false), among: [internalDisplay]))
print("PASS: safety rules for built-in, last, lid-closed, and offline displays.")
