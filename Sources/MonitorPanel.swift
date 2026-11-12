import SwiftUI
import ServiceManagement

struct MonitorPanel: View {
    @ObservedObject var controller: DisplayController
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "display.2")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.teal)
                    .frame(width: 46, height: 46)
                    .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Deextend").font(.title2.weight(.semibold))
                    Text(L.text("app.tagline"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if controller.busy { ProgressView().controlSize(.small) }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle().fill(controller.held.isEmpty ? Color.green : Color.orange).frame(width: 7, height: 7)
                    Text(controller.held.isEmpty ? L.text("panel.connected") : L.text("panel.paused"))
                        .font(.subheadline.weight(.medium))
                }
                Text(L.text("panel.explanation"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                Text(L.text("panel.displays")).font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.3).foregroundStyle(.secondary)
                if controller.external.isEmpty {
                    Label(L.text("panel.noDisplays"), systemImage: "cable.connector")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(controller.external) { display in
                    displayRow(display)
                }
                // Keep a way to clear pause intent if the hub was physically unplugged.
                if controller.held.contains(where: { id in !controller.external.contains { $0.id == id } }) {
                    Button(L.text("action.reset")) {
                        Task { _ = await controller.restoreAll() }
                    }.disabled(controller.busy)
                }
            }

            if !controller.canDisconnect {
                Label(L.text("panel.lidRequired"), systemImage: "laptopcomputer")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = controller.error ?? loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            } else if let message = controller.message {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Toggle(L.text("settings.login"), isOn: $loginEnabled)
                .toggleStyle(.switch).controlSize(.small).font(.callout)
                .onChange(of: loginEnabled) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginError = SMAppService.mainApp.status == .requiresApproval
                            ? L.text("settings.loginApproval") : nil
                    } catch {
                        loginError = error.localizedDescription
                    }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                }
            HStack {
                Text(L.text("panel.restoreOnQuit"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button(L.text("action.quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 370)
        .onAppear {
            controller.refresh()
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    private func displayRow(_ display: DisplayDevice) -> some View {
        let paused = controller.held.contains(display.id) || !display.online
        return HStack(spacing: 12) {
            Group {
                if paused { Image(nsImage: StatusImages.pausedDisplay) }
                else { Image(systemName: "display").font(.system(size: 21)) }
            }
                .foregroundStyle(paused ? Color.secondary : Color.teal)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(display.name).font(.callout.weight(.semibold)).lineLimit(1)
                Text(display.online ? L.text("display.available") : L.text("display.disconnected"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(paused ? L.text("action.connect") : L.text("action.disconnect")) {
                Task { await controller.toggle(display) }
            }
            .buttonStyle(.borderedProminent).tint(paused ? .teal : .gray)
            .controlSize(.small)
            .disabled(controller.busy || !controller.bridge.available || (!paused && !controller.canDisconnect))
        }
        .padding(.vertical, 4)
    }
}
