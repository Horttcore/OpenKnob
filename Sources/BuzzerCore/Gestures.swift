import Foundation

public enum KnobGesture: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case press
    case turnRight
    case turnLeft

    public var title: String {
        switch self {
        case .press: return "Press"
        case .turnRight: return "Turn right"
        case .turnLeft: return "Turn left"
        }
    }

    public var instruction: String {
        switch self {
        case .press: return "Press the knob once."
        case .turnRight: return "Turn the knob one click to the right."
        case .turnLeft: return "Turn the knob one click to the left."
        }
    }
}

public struct GestureRule: Codable, Equatable, Sendable {
    public var gesture: KnobGesture
    /// Full status byte, channel included.
    public var status: UInt8
    public var data1: UInt8
    /// Nil matches every value on this controller.
    public var data2: UInt8?

    public init(gesture: KnobGesture, status: UInt8, data1: UInt8, data2: UInt8?) {
        self.gesture = gesture
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }

    public var summary: String {
        if let data2 {
            return String(format: "%02X %02X %02X", status, data1, data2)
        }
        return String(format: "%02X %02X **", status, data1)
    }
}

public enum GestureLearner {
    public static func rule(
        for gesture: KnobGesture,
        message: MidiMessage,
        matchAnyValue: Bool
    ) -> GestureRule {
        GestureRule(
            gesture: gesture,
            status: message.status,
            data1: message.data1,
            data2: matchAnyValue ? nil : message.data2
        )
    }

    /// Replaces the rule for the same gesture and drops other rules that would
    /// claim the same message.
    public static func apply(_ rule: GestureRule, to rules: [GestureRule]) -> [GestureRule] {
        let kept = rules.filter { existing in
            if existing.gesture == rule.gesture {
                return false
            }
            let sameControl = existing.status == rule.status && existing.data1 == rule.data1
            guard sameControl else { return true }
            if rule.data2 == nil || existing.data2 == nil || existing.data2 == rule.data2 {
                return false
            }
            return true
        }
        return kept + [rule]
    }
}

public struct GestureDecoder: Equatable, Sendable {
    public var rules: [GestureRule]

    public init(rules: [GestureRule]) {
        self.rules = rules
    }

    public func gesture(for message: MidiMessage) -> KnobGesture? {
        if let exact = rules.first(where: {
            $0.status == message.status && $0.data1 == message.data1 && $0.data2 == message.data2
        }) {
            return exact.gesture
        }
        return rules.first(where: {
            $0.status == message.status && $0.data1 == message.data1 && $0.data2 == nil
        })?.gesture
    }
}

public struct GestureGate: Equatable, Sendable {
    public var lastFired: [KnobGesture: Date]

    public init(lastFired: [KnobGesture: Date] = [:]) {
        self.lastFired = lastFired
    }

    public mutating func allow(
        _ gesture: KnobGesture,
        at date: Date,
        cooldown: TimeInterval
    ) -> Bool {
        if cooldown > 0, let previous = lastFired[gesture], date.timeIntervalSince(previous) < cooldown {
            return false
        }
        lastFired[gesture] = date
        return true
    }
}

public struct GestureRouter: Sendable {
    public var rules: [GestureRule]
    public var gate: GestureGate
    public var pressCooldown: TimeInterval
    public var turnCooldown: TimeInterval

    public init(
        rules: [GestureRule],
        gate: GestureGate = GestureGate(),
        pressCooldown: TimeInterval = 0.18,
        turnCooldown: TimeInterval = 0
    ) {
        self.rules = rules
        self.gate = gate
        self.pressCooldown = pressCooldown
        self.turnCooldown = turnCooldown
    }

    public mutating func handle(_ message: MidiMessage, at date: Date = Date()) -> KnobGesture? {
        if LedProtocol.isLedTraffic(message) {
            return nil
        }
        guard let gesture = GestureDecoder(rules: rules).gesture(for: message) else {
            return nil
        }
        let cooldown = gesture == .press ? pressCooldown : turnCooldown
        guard gate.allow(gesture, at: date, cooldown: cooldown) else {
            return nil
        }
        return gesture
    }
}
