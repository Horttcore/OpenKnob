import Foundation

public enum SessionNotice: Equatable, Sendable {
    case learned(GestureRule)
    case performed(KnobGesture, [BuzzerAction])

    public var summary: String {
        switch self {
        case let .learned(rule):
            return "learned \(rule.gesture.title) as \(rule.summary)"
        case let .performed(gesture, actions):
            let detail = actions.map(\.summary).joined(separator: ", ")
            if detail.isEmpty {
                return "\(gesture.title) with no action"
            }
            return "\(gesture.title) → \(detail)"
        }
    }
}

/// Knob learn and dispatch without MIDI hardware or AppKit.
/// The Mac app feeds the same bytes it reads from CoreMIDI.
public struct BuzzerSession: Sendable {
    public var config: AppConfig
    public var learning: KnobGesture?
    public var matchAnyValue: Bool
    public private(set) var gate: GestureGate

    public init(config: AppConfig = .default, matchAnyValue: Bool = false) {
        var config = config
        config.normalize()
        self.config = config
        self.learning = nil
        self.matchAnyValue = matchAnyValue
        self.gate = GestureGate()
    }

    public mutating func receive(_ bytes: [UInt8], at date: Date = Date()) -> [SessionNotice] {
        let messages = MidiMessage.parseChannelMessages(from: bytes)
        if let learning {
            guard let message = messages.first(where: { !LedProtocol.isLedTraffic($0) }) else {
                return []
            }
            let rule = GestureLearner.rule(
                for: learning,
                message: message,
                matchAnyValue: matchAnyValue
            )
            config.rules = GestureLearner.apply(rule, to: config.rules)
            self.learning = nil
            return [.learned(rule)]
        }

        var router = GestureRouter(
            rules: config.rules,
            gate: gate,
            pressCooldown: TimeInterval(config.pressCooldownMs) / 1000,
            turnCooldown: TimeInterval(config.turnCooldownMs) / 1000
        )
        var notices: [SessionNotice] = []
        for message in messages {
            guard let gesture = router.handle(message, at: date) else { continue }
            notices.append(.performed(gesture, config.actions(for: gesture)))
        }
        gate = router.gate
        return notices
    }
}

public struct SimulationStep: Equatable, Sendable {
    public var title: String
    public var incoming: String
    public var notices: [SessionNotice]

    public init(title: String, incoming: String, notices: [SessionNotice]) {
        self.title = title
        self.incoming = incoming
        self.notices = notices
    }
}

public enum KnobSimulation {
    /// A fake knob: press is note 48, turns share CC 16 with values 1 and 127,
    /// and LED echoes use CC 70. Timestamps are fixed so the press cooldown is deterministic.
    public static func run() -> [SimulationStep] {
        var session = BuzzerSession()
        let start = Date(timeIntervalSince1970: 10_000)
        var steps: [SimulationStep] = []

        func feed(_ title: String, hex: String, at offset: TimeInterval, learn: KnobGesture? = nil) -> SimulationStep {
            session.learning = learn
            let bytes = HexCodec.bytes(from: hex) ?? []
            let notices = session.receive(bytes, at: start.addingTimeInterval(offset))
            let step = SimulationStep(title: title, incoming: HexCodec.string(from: bytes), notices: notices)
            steps.append(step)
            return step
        }

        _ = feed(
            "Learn press, ignoring an LED echo in the same packet",
            hex: "BB 46 10 90 30 7F",
            at: 0,
            learn: .press
        )
        _ = feed("Learn turn right", hex: "BB 10 01", at: 1, learn: .turnRight)
        _ = feed("Learn turn left", hex: "BB 10 7F", at: 2, learn: .turnLeft)
        _ = feed("LED echo does nothing", hex: "BB 46 40", at: 3)
        _ = feed("Press", hex: "90 30 7F", at: 4)
        _ = feed("Press again inside the cooldown", hex: "90 30 7F", at: 4.05)
        _ = feed("Press after the cooldown", hex: "90 30 7F", at: 4.4)
        _ = feed("Two fast turns right", hex: "BB 10 01 BB 10 01", at: 5)
        _ = feed("Turn left", hex: "BB 10 7F", at: 6)
        return steps
    }

    public static func transcript() -> String {
        run().map { step in
            let body = step.notices.isEmpty ? "  (no gesture)" : step.notices.map { "  \($0.summary)" }.joined(separator: "\n")
            return "\(step.title)\n  ← \(step.incoming)\n\(body)"
        }.joined(separator: "\n")
    }
}
