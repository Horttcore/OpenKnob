import Foundation

public struct MidiMessage: Equatable, Hashable, Sendable, Codable {
    public var status: UInt8
    public var data1: UInt8
    public var data2: UInt8

    public init(status: UInt8, data1: UInt8, data2: UInt8) {
        self.status = status
        self.data1 = data1
        self.data2 = data2
    }

    public var hex: String {
        String(format: "%02X %02X %02X", status, data1, data2)
    }

    /// Pulls 3-byte channel messages out of a MIDI byte stream.
    /// System real-time bytes and sysex are skipped. Program change and
    /// channel pressure (2-byte messages) are skipped because the knob
    /// learner stores a status plus two data bytes.
    public static func parseChannelMessages(from bytes: [UInt8]) -> [MidiMessage] {
        var messages: [MidiMessage] = []
        var index = 0
        while index < bytes.count {
            let status = bytes[index]
            if status < 0x80 {
                index += 1
                continue
            }
            if status >= 0xF8 {
                index += 1
                continue
            }
            if status == 0xF0 {
                index += 1
                while index < bytes.count, bytes[index] != 0xF7 {
                    index += 1
                }
                if index < bytes.count {
                    index += 1
                }
                continue
            }
            if status == 0xF7 || status >= 0xF4 {
                index += 1
                continue
            }
            if status == 0xF1 || status == 0xF3 {
                index += min(2, bytes.count - index)
                continue
            }
            if status == 0xF2 {
                index += min(3, bytes.count - index)
                continue
            }
            let kind = status & 0xF0
            let length = (kind == 0xC0 || kind == 0xD0) ? 2 : 3
            guard index + length <= bytes.count else { break }
            if length == 3 {
                messages.append(
                    MidiMessage(status: status, data1: bytes[index + 1], data2: bytes[index + 2])
                )
            }
            index += length
        }
        return messages
    }
}

public enum HexCodec {
    public static func bytes(from text: String) -> [UInt8]? {
        var stripped = text
        while let range = stripped.range(of: "0x", options: .caseInsensitive) {
            stripped.removeSubrange(range)
        }
        let digits = stripped.unicodeScalars.filter { hexDigits.contains($0) }
        let cleaned = String(String.UnicodeScalarView(digits))
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    public static func string(from bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
}
