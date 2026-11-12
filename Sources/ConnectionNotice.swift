import AppKit
import SwiftUI

/// Separate from the menu popover: a compact, nonactivating notice on the built-in screen.
@MainActor
final class ConnectionNoticePresenter {
    private let controller: DisplayController
    private var panel: NSPanel?
    private var pending: [DisplayDevice] = []
    private var lastAnnouncement: [String: Date] = [:]
    private var dismissal: Task<Void, Never>?

    init(controller: DisplayController) { self.controller = controller }

    func announce(_ display: DisplayDevice) {
        guard Date().timeIntervalSince(lastAnnouncement[display.id] ?? .distantPast) >= 30 else { return }
        lastAnnouncement[display.id] = Date()
        guard !pending.contains(where: { $0.id == display.id }) else { return }
        pending.append(display)
        if pending.count == 1 { presentNext() }
    }

    func clear(_ identity: String) {
        let wasCurrent = pending.first?.id == identity
        pending.removeAll { $0.id == identity }
        lastAnnouncement[identity] = nil
        if wasCurrent { presentNext() }
    }

    private func presentNext() {
        dismissal?.cancel()
        panel?.orderOut(nil)
        panel = nil
        guard let display = pending.first else { return }
        let view = ConnectionNoticeView(controller: controller, display: display,
                                        dismiss: { [weak self] in self?.dismissCurrent() },
                                        reconnect: { [weak self] in
            guard let self else { return false }
            dismissal?.cancel()
            let success = await controller.reconnect(display.id)
            if success { clear(display.id) }
            return success
        })
        let hosting = NSHostingView(rootView: view)
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor)
        ])
        let size = hosting.fittingSize
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = L.text("notice.title")
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = material
        // The external has just been disabled: always put the notice on a usable display.
        let screen = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return CGDisplayIsBuiltin(id.uint32Value) != 0
        } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 18, y: frame.maxY - size.height - 18))
        }
        panel = window
        window.orderFrontRegardless()
        // Keep each notice available for 20 seconds without taking focus from the user's app.
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 20_000_000_000) }
            catch { return }
            self?.dismissCurrent()
        }
    }

    private func dismissCurrent() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
        presentNext()
    }
}

private struct ConnectionNoticeView: View {
    @ObservedObject var controller: DisplayController
    let display: DisplayDevice
    let dismiss: () -> Void
    let reconnect: () async -> Bool
    @State private var reconnecting = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "display").font(.system(size: 23)).foregroundStyle(.teal)
                    .frame(width: 38, height: 38)
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Deextend").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    Text(L.text("notice.title")).font(.callout.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(L.text("action.dismiss"))
            }
            Text(L.text("notice.body", display.name))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(L.text("action.reconnect")) {
                    reconnecting = true
                    Task { @MainActor in
                        if !(await reconnect()) { failure = controller.error ?? L.text("error.unreachable") }
                        reconnecting = false
                    }
                }
                .buttonStyle(.borderedProminent).tint(.teal)
                .disabled(controller.busy || reconnecting)
            }
        }
        .padding(16)
        .frame(width: 350)
    }
}
