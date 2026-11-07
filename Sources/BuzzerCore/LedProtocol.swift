import Foundation

/// timeBuzzer RGB rings, as used by community LED tools.
/// Channel 12 control change (status 0xBB). Three segments, CC 70–78.
/// Each channel is 0–127, half of an 8-bit RGB component.
public enum LedProtocol {
    public static let channel: UInt8 = 12
    public static let ccStatus: UInt8 = 0xB0 | (channel - 1)
    public static let firstController: UInt8 = 70
    public static let lastController: UInt8 = 78

    public struct RGB: Equatable, Sendable {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8

        public init(r: UInt8, g: UInt8, b: UInt8) {
            self.r = r
            self.g = g
            self.b = b
        }
    }

    public static func rgb(hex: String) -> RGB? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            text.removeFirst()
        }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return RGB(
            r: UInt8((value >> 16) & 0xFF),
            g: UInt8((value >> 8) & 0xFF),
            b: UInt8(value & 0xFF)
        )
    }

    public static func normalizedHex(_ hex: String) -> String? {
        guard let rgb = rgb(hex: hex) else { return nil }
        return String(format: "%02X%02X%02X", rgb.r, rgb.g, rgb.b)
    }

    public static func messages(segment: Int, rgb: RGB) -> [[UInt8]] {
        guard (0...2).contains(segment) else { return [] }
        let base = Int(firstController) + (3 * segment)
        return [rgb.r, rgb.g, rgb.b].enumerated().map { offset, component in
            [ccStatus, UInt8(base + offset), component / 2]
        }
    }

    public static func messages(segment: Int?, hex: String) -> [[UInt8]] {
        guard let rgb = rgb(hex: hex) else { return [] }
        if let segment {
            return messages(segment: segment, rgb: rgb)
        }
        return (0..<3).flatMap { messages(segment: $0, rgb: rgb) }
    }

    public static func isLedTraffic(_ message: MidiMessage) -> Bool {
        message.status == ccStatus
            && message.data1 >= firstController
            && message.data1 <= lastController
    }
}
