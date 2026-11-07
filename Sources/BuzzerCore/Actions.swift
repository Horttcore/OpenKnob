import Foundation

public enum KeyModifier: String, Codable, CaseIterable, Equatable, Sendable {
    case command
    case option
    case control
    case shift

    public var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }
}

public enum MediaControl: String, Codable, CaseIterable, Equatable, Sendable {
    case volumeUp
    case volumeDown
    case mute
    case playPause

    public var title: String {
        switch self {
        case .volumeUp: return "Volume up"
        case .volumeDown: return "Volume down"
        case .mute: return "Mute"
        case .playPause: return "Play / pause"
        }
    }
}

public enum BuzzerAction: Codable, Equatable, Sendable {
    case keystroke(key: String, modifiers: [KeyModifier])
    case media(MediaControl)
    case setLED(hex: String)
    case shell(String)
    case openURL(String)

    public var summary: String {
        switch self {
        case let .keystroke(key, modifiers):
            let prefix = modifiers.map(\.symbol).joined()
            let name = key.isEmpty ? "key" : key
            return prefix.isEmpty ? name : prefix + name
        case let .media(control):
            return control.title
        case let .setLED(hex):
            return "LED #\(LedProtocol.normalizedHex(hex) ?? hex)"
        case let .shell(command):
            let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Shell command" : "Shell · \(trimmed)"
        case let .openURL(url):
            return url.isEmpty ? "Open URL" : "Open \(url)"
        }
    }
}

public enum KeyMap {
    /// ANSI virtual key codes used by CGEvent on macOS.
    public static func virtualKey(for name: String) -> UInt16? {
        let key = aliases[normalize(name)] ?? normalize(name)
        return codes[key]
    }

    public static func normalize(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let aliases: [String: String] = [
        "enter": "return",
        "esc": "escape",
        "spacebar": "space",
        "arrowleft": "left",
        "arrowright": "right",
        "arrowup": "up",
        "arrowdown": "down",
        "leftarrow": "left",
        "rightarrow": "right",
        "uparrow": "up",
        "downarrow": "down",
        "backspace": "delete",
        "del": "forwarddelete",
    ]

    private static let codes: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05,
        "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "equals": 0x18, "=": 0x18, "9": 0x19, "7": 0x1A, "minus": 0x1B, "-": 0x1B,
        "8": 0x1C, "0": 0x1D, "rightbracket": 0x1E, "]": 0x1E,
        "o": 0x1F, "u": 0x20, "leftbracket": 0x21, "[": 0x21,
        "i": 0x22, "p": 0x23, "return": 0x24, "l": 0x25, "j": 0x26,
        "quote": 0x27, "'": 0x27, "k": 0x28, "semicolon": 0x29, ";": 0x29,
        "backslash": 0x2A, "\\": 0x2A, "comma": 0x2B, ",": 0x2B,
        "slash": 0x2C, "/": 0x2C, "n": 0x2D, "m": 0x2E, "period": 0x2F, ".": 0x2F,
        "tab": 0x30, "space": 0x31, "grave": 0x32, "`": 0x32,
        "delete": 0x33, "escape": 0x35,
        "f5": 0x60, "f6": 0x61, "f7": 0x62, "f3": 0x63, "f8": 0x64, "f9": 0x65,
        "f11": 0x67, "f10": 0x6D, "f12": 0x6F, "f4": 0x76, "f2": 0x78, "f1": 0x7A,
        "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "end": 0x77, "pagedown": 0x79,
        "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    ]
}
