#if os(macOS)
import AppKit
import ApplicationServices
import BuzzerCore
import CoreGraphics
import Foundation

enum ActionRunner {
    @MainActor
    static func perform(_ action: BuzzerAction, model: AppModel) {
        switch action {
        case let .keystroke(key, modifiers):
            guard let code = KeyMap.virtualKey(for: key) else {
                model.note("Unknown key “\(key)”. Try space, return, left, or a letter.")
                return
            }
            postKey(CGKeyCode(code), modifiers: modifiers)
        case let .media(control):
            postMedia(control)
        case let .setLED(hex):
            model.sendLED(hex: hex)
        case let .shell(command):
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            runShell(trimmed, model: model)
        case let .openURL(raw):
            guard let url = URL(string: raw), url.scheme != nil else {
                model.note("URL needs a scheme, like https://")
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    private static func postKey(_ code: CGKeyCode, modifiers: [KeyModifier]) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        var flags = CGEventFlags()
        for modifier in modifiers {
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .shift: flags.insert(.maskShift)
            }
        }
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postMedia(_ control: MediaControl) {
        let key: Int32
        switch control {
        case .volumeUp: key = 0
        case .volumeDown: key = 1
        case .mute: key = 7
        case .playPause: key = 16
        }
        postSystemDefined(key: key, down: true)
        postSystemDefined(key: key, down: false)
    }

    private static func postSystemDefined(key: Int32, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    @MainActor
    private static func runShell(_ command: String, model: AppModel) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            model.note("Could not run the command. \(error.localizedDescription)")
        }
    }
}

enum Accessibility {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ]
        for raw in urls {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
#endif
