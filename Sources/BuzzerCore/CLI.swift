import Foundation

public enum BuzzerCLI {
    public static func run(arguments: [String]) -> Int32 {
        let args = arguments.filter { $0 != "--cli" }
        guard let command = args.first else {
            print(help)
            return 0
        }
        switch command {
        case "led":
            return led(Array(args.dropFirst()))
        case "parse":
            return parse(Array(args.dropFirst()))
        case "help", "-h", "--help":
            print(help)
            return 0
        default:
            return fail("Unknown command \(command)\n\(help)")
        }
    }

    private static func led(_ args: [String]) -> Int32 {
        guard let hex = args.first else {
            return fail("Usage: BuzzerMac --cli led <hex> [all|0|1|2]")
        }
        let segment: Int?
        if args.count < 2 || args[1] == "all" {
            segment = nil
        } else if let index = Int(args[1]), (0...2).contains(index) {
            segment = index
        } else {
            return fail("Segment must be all, 0, 1, or 2.")
        }
        let packets = LedProtocol.messages(segment: segment, hex: hex)
        guard !packets.isEmpty else {
            return fail("Color must be a 6-digit hex value, like FF8800.")
        }
        for packet in packets {
            print(packet.map { String(format: "%02X", $0) }.joined(separator: " "))
        }
        return 0
    }

    private static func parse(_ args: [String]) -> Int32 {
        let text = args.joined(separator: " ")
        guard let bytes = HexCodec.bytes(from: text) else {
            return fail("Give an even number of hex digits.")
        }
        let messages = MidiMessage.parseChannelMessages(from: bytes)
        if messages.isEmpty {
            print("No 3-byte channel messages.")
            return 0
        }
        for message in messages {
            let led = LedProtocol.isLedTraffic(message) ? "  led" : ""
            print("\(message.hex)\(led)")
        }
        return 0
    }

    private static let help = """
    BuzzerMac --cli led <hex> [all|0|1|2]
    BuzzerMac --cli parse <hex bytes>
    """

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }
}
