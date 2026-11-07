#if os(macOS)
import BuzzerCore
import Foundation
import ServiceManagement
import SwiftUI

struct LogLine: Identifiable, Equatable {
    enum Direction: Equatable {
        case incoming
        case outgoing
        case info
    }

    let id = UUID()
    var date = Date()
    var text: String
    var direction: Direction
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var ports: [MidiEndpointInfo] = []
    @Published var portSelection = ""
    @Published private(set) var connectedPort: String?
    @Published private(set) var canPaint = false
    @Published private(set) var log: [LogLine] = []
    @Published var config: AppConfig
    @Published var learning: KnobGesture?
    @Published var matchAnyValue = false
    @Published var statusMessage = "Plug in the buzzer."
    @Published var accessibilityTrusted = true
    @Published var paintAllRings = true
    @Published var ringIndex = 0
    @Published var colorHex: String
    @Published var injectHex = ""

    private let midi = MidiService()
    private let store: ConfigStore
    private var session: BuzzerSession
    private var started = false
    private var pollTask: Task<Void, Never>?
    private var colorTask: Task<Void, Never>?
    private var learnTask: Task<Void, Never>?
    private var acceptsColorSend = false
    private var paintedPort: String?

    init(store: ConfigStore? = nil) {
        let store = store ?? ConfigStore(directory: ConfigStore.defaultDirectory())
        self.store = store
        var loaded = store.load()
        loaded.normalize()
        session = BuzzerSession(config: loaded)
        config = session.config
        colorHex = loaded.connectColorHex
        portSelection = loaded.portName ?? ""
    }

    var isConnected: Bool { connectedPort != nil }

    func start() {
        guard !started else { return }
        started = true
        if let error = midi.start(onBytes: { [weak self] bytes in
            Task { @MainActor in
                self?.ingest(bytes)
            }
        }, onSetup: { [weak self] in
            Task { @MainActor in
                self?.refreshPorts()
            }
        }) {
            note(error)
        }
        refreshPorts()
        refreshAccessibility()
        acceptsColorSend = true
        if config.launchAtLogin {
            applyLaunchAtLogin(true, announce: false)
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await self?.refreshPorts()
            }
        }
    }

    func refreshAccessibility() {
        accessibilityTrusted = Accessibility.isTrusted
    }

    func refreshPorts() {
        let listed = midi.sources()
        if listed != ports {
            ports = listed
        }
        let names = listed.map(\.name)
        let saved = portSelection.isEmpty ? nil : portSelection
        guard let chosen = PortMatch.choose(ports: names, saved: saved) else {
            if connectedPort != nil {
                midi.disconnect()
                connectedPort = nil
                canPaint = false
                paintedPort = nil
            }
            statusMessage = names.isEmpty
                ? "No MIDI inputs yet. Plug in the buzzer."
                : "Pick the buzzer in the MIDI port menu."
            return
        }
        if connectedPort != chosen {
            if let warning = midi.connect(name: chosen) {
                note(warning)
            }
            connectedPort = midi.currentSourceName()
            canPaint = midi.canSend()
            if connectedPort == chosen {
                note("Connected to \(chosen).")
                if config.sendColorOnConnect, paintedPort != chosen {
                    paintedPort = chosen
                    sendLED(hex: config.connectColorHex)
                }
            } else {
                connectedPort = nil
                canPaint = false
            }
        } else {
            canPaint = midi.canSend()
        }
    }

    func choosePort(_ selection: String) {
        portSelection = selection
        config.portName = selection.isEmpty ? nil : selection
        save()
        if connectedPort != nil {
            midi.disconnect()
            connectedPort = nil
            paintedPort = nil
        }
        refreshPorts()
    }

    func colorDraftChanged() {
        guard let normalized = LedProtocol.normalizedHex(colorHex) else { return }
        if config.connectColorHex != normalized {
            config.connectColorHex = normalized
            save()
        }
        scheduleColorSend(normalized)
    }

    func setRing(all: Bool, index: Int) {
        paintAllRings = all
        ringIndex = index
        if let normalized = LedProtocol.normalizedHex(colorHex) {
            scheduleColorSend(normalized)
        }
    }

    func sendLED(hex: String) {
        let segment: Int? = paintAllRings ? nil : ringIndex
        let packets = LedProtocol.messages(segment: segment, hex: hex)
        guard !packets.isEmpty else {
            note("Color needs 6 hex digits, like FF8800.")
            return
        }
        colorTask?.cancel()
        colorTask = Task { [weak self] in
            for packet in packets {
                guard let self else { return }
                if let error = self.midi.send(packet) {
                    self.append(LogLine(text: error, direction: .info))
                    self.statusMessage = error
                    return
                }
                self.append(LogLine(text: "→ \(HexCodec.string(from: packet))", direction: .outgoing))
                try? await Task.sleep(nanoseconds: 2_000_000)
            }
        }
    }

    func beginLearn(_ gesture: KnobGesture) {
        learning = gesture
        if matchAnyValue {
            note("\(gesture.instruction) Any value on that control will count.")
        } else {
            note(gesture.instruction)
        }
        learnTask?.cancel()
        learnTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard let self, self.learning == gesture else { return }
            self.learning = nil
            self.note("Learn timed out. Try again.")
        }
    }

    func cancelLearn() {
        learning = nil
        learnTask?.cancel()
        note("Learn cancelled.")
    }

    func clearRule(_ gesture: KnobGesture) {
        config.rules.removeAll { $0.gesture == gesture }
        save()
        note("\(gesture.title) forgotten.")
    }

    func setActions(_ actions: [BuzzerAction], for gesture: KnobGesture) {
        if let index = config.bindings.firstIndex(where: { $0.gesture == gesture }) {
            config.bindings[index].actions = actions
        } else {
            config.bindings.append(GestureBinding(gesture: gesture, actions: actions))
        }
        config.normalize()
        save()
    }

    func inject() {
        guard let bytes = HexCodec.bytes(from: injectHex) else {
            note("Inject needs hex, like BB 10 01.")
            return
        }
        ingest(bytes)
    }

    func sendInjected() {
        guard let bytes = HexCodec.bytes(from: injectHex) else {
            note("Send needs hex, like BB 46 7F.")
            return
        }
        if let error = midi.send(bytes) {
            note(error)
            return
        }
        append(LogLine(text: "→ \(HexCodec.string(from: bytes))", direction: .outgoing))
    }

    func setSendColorOnConnect(_ enabled: Bool) {
        config.sendColorOnConnect = enabled
        save()
    }

    func setCooldown(press: Int? = nil, turn: Int? = nil) {
        if let press { config.pressCooldownMs = max(0, press) }
        if let turn { config.turnCooldownMs = max(0, turn) }
        save()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        config.launchAtLogin = enabled
        save()
        applyLaunchAtLogin(enabled, announce: true)
    }

    func copyLog() -> String {
        log.map { line in
            let stamp = Self.stamp.string(from: line.date)
            return "\(stamp)  \(line.text)"
        }.joined(separator: "\n")
    }

    func note(_ text: String) {
        statusMessage = text
        append(LogLine(text: text, direction: .info))
    }

    private func scheduleColorSend(_ hex: String) {
        guard acceptsColorSend, learning == nil else { return }
        colorTask?.cancel()
        colorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.sendLED(hex: hex)
        }
    }

    private func ingest(_ bytes: [UInt8]) {
        append(LogLine(text: "← \(HexCodec.string(from: bytes))", direction: .incoming))
        session.config = config
        session.learning = learning
        session.matchAnyValue = matchAnyValue
        let notices = session.receive(bytes)
        config = session.config
        learning = session.learning
        for notice in notices {
            switch notice {
            case let .learned(rule):
                learnTask?.cancel()
                save()
                note("\(rule.gesture.title) learned as \(rule.summary).")
            case let .performed(gesture, actions):
                statusMessage = gesture.title
                for action in actions {
                    ActionRunner.perform(action, model: self)
                }
            }
        }
    }

    private func save() {
        do {
            try store.save(config)
        } catch {
            statusMessage = "Could not save settings. \(error.localizedDescription)"
        }
    }

    private func append(_ line: LogLine) {
        log.append(line)
        if log.count > 80 {
            log.removeFirst(log.count - 80)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool, announce: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            if announce {
                note(enabled ? "Buzzer will open at login." : "Launch at login is off.")
            }
        } catch {
            if announce {
                note("Launch at login needs the packaged Buzzer app. \(error.localizedDescription)")
            }
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
#endif
