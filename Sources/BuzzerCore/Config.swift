import Foundation

public struct GestureBinding: Codable, Equatable, Sendable {
    public var gesture: KnobGesture
    public var actions: [BuzzerAction]

    public init(gesture: KnobGesture, actions: [BuzzerAction]) {
        self.gesture = gesture
        self.actions = actions
    }
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var portName: String?
    public var rules: [GestureRule]
    public var bindings: [GestureBinding]
    public var connectColorHex: String
    public var sendColorOnConnect: Bool
    public var pressCooldownMs: Int
    public var turnCooldownMs: Int
    public var launchAtLogin: Bool

    public init(
        portName: String?,
        rules: [GestureRule],
        bindings: [GestureBinding],
        connectColorHex: String,
        sendColorOnConnect: Bool,
        pressCooldownMs: Int,
        turnCooldownMs: Int,
        launchAtLogin: Bool
    ) {
        self.portName = portName
        self.rules = rules
        self.bindings = bindings
        self.connectColorHex = connectColorHex
        self.sendColorOnConnect = sendColorOnConnect
        self.pressCooldownMs = pressCooldownMs
        self.turnCooldownMs = turnCooldownMs
        self.launchAtLogin = launchAtLogin
    }

    public static var `default`: AppConfig {
        AppConfig(
            portName: nil,
            rules: [],
            bindings: [
                GestureBinding(gesture: .press, actions: [.media(.playPause)]),
                GestureBinding(gesture: .turnRight, actions: [.media(.volumeUp)]),
                GestureBinding(gesture: .turnLeft, actions: [.media(.volumeDown)]),
            ],
            connectColorHex: "FFB43C",
            sendColorOnConnect: true,
            pressCooldownMs: 180,
            turnCooldownMs: 0,
            launchAtLogin: false
        )
    }

    public func actions(for gesture: KnobGesture) -> [BuzzerAction] {
        bindings.first { $0.gesture == gesture }?.actions ?? []
    }

    public func rule(for gesture: KnobGesture) -> GestureRule? {
        rules.first { $0.gesture == gesture }
    }

    public mutating func normalize() {
        if LedProtocol.normalizedHex(connectColorHex) == nil {
            connectColorHex = "FFB43C"
        } else if let hex = LedProtocol.normalizedHex(connectColorHex) {
            connectColorHex = hex
        }
        pressCooldownMs = max(0, pressCooldownMs)
        turnCooldownMs = max(0, turnCooldownMs)
        bindings = KnobGesture.allCases.map { gesture in
            GestureBinding(gesture: gesture, actions: actions(for: gesture))
        }
    }
}

public struct ConfigStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL {
        directory.appendingPathComponent("config.json")
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BuzzerMac", isDirectory: true)
    }

    public func load() -> AppConfig {
        guard
            let data = try? Data(contentsOf: fileURL),
            var config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else {
            return .default
        }
        config.normalize()
        return config
    }

    public func save(_ config: AppConfig) throws {
        var config = config
        config.normalize()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: fileURL, options: .atomic)
    }
}

public enum PortMatch {
    public static let hints = ["timebuzzer", "buzzer", "ideas in logic", "ideas"]

    public static func choose(ports: [String], saved: String?) -> String? {
        if let saved, ports.contains(saved) {
            return saved
        }
        return ports.first { port in
            let lower = port.lowercased()
            return hints.contains { lower.contains($0) }
        }
    }
}
