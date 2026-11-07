#if os(macOS)
import AppKit
import SwiftUI

struct MenuLabel: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: model.isConnected ? "dial.medium.fill" : "dial.medium")
            Text("Buzzer")
        }
        .onAppear { model.start() }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(model.isConnected ? Color(red: 0.18, green: 0.62, blue: 0.32) : Color.secondary.opacity(0.45))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isConnected ? "Connected" : "Not connected")
                        .font(.headline)
                    Text(model.connectedPort ?? "Waiting for the knob")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("Controls…") { reveal() }
            Button("Quit Buzzer") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .onAppear { model.start() }
    }

    private func reveal() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
#endif
