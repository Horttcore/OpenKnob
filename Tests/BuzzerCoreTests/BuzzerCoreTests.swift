import XCTest
@testable import BuzzerCore

final class BuzzerCoreTests: XCTestCase {
    func testLedMessagesUseChannel12AndHalfBrightness() {
        let packets = LedProtocol.messages(segment: 0, hex: "#FF8001")
        XCTAssertEqual(packets.count, 3)
        XCTAssertEqual(packets[0], [0xBB, 70, 127])
        XCTAssertEqual(packets[1], [0xBB, 71, 64])
        XCTAssertEqual(packets[2], [0xBB, 72, 0])
    }

    func testLedSegmentsAndAllRings() {
        let second = LedProtocol.messages(segment: 1, hex: "0000FF")
        XCTAssertEqual(second.map { $0[1] }, [73, 74, 75])
        let third = LedProtocol.messages(segment: 2, hex: "00FF00")
        XCTAssertEqual(third[0][1], 76)
        let all = LedProtocol.messages(segment: nil, hex: "FFFFFF")
        XCTAssertEqual(all.count, 9)
        XCTAssertEqual(all.map { $0[1] }, [70, 71, 72, 73, 74, 75, 76, 77, 78])
        XCTAssertTrue(all.allSatisfy { $0[2] == 127 })
        XCTAssertTrue(LedProtocol.messages(segment: 3, hex: "FFFFFF").isEmpty)
        XCTAssertTrue(LedProtocol.messages(segment: nil, hex: "GG0000").isEmpty)
    }

    func testLedTrafficDetection() {
        XCTAssertTrue(LedProtocol.isLedTraffic(MidiMessage(status: 0xBB, data1: 70, data2: 1)))
        XCTAssertTrue(LedProtocol.isLedTraffic(MidiMessage(status: 0xBB, data1: 78, data2: 0)))
        XCTAssertFalse(LedProtocol.isLedTraffic(MidiMessage(status: 0xBB, data1: 69, data2: 1)))
        XCTAssertFalse(LedProtocol.isLedTraffic(MidiMessage(status: 0xBA, data1: 70, data2: 1)))
    }

    func testParseChannelMessagesSkipsRealtimeAndSysex() {
        let bytes = HexCodec.bytes(from: "F8 F0 01 02 F7 90 3C 7F BB 10 01")!
        let messages = MidiMessage.parseChannelMessages(from: bytes)
        XCTAssertEqual(messages, [
            MidiMessage(status: 0x90, data1: 0x3C, data2: 0x7F),
            MidiMessage(status: 0xBB, data1: 0x10, data2: 0x01),
        ])
    }

    func testHexCodecStripsPrefixes() {
        XCTAssertEqual(HexCodec.bytes(from: "0xBB 0x46 0x7F"), [0xBB, 0x46, 0x7F])
        XCTAssertEqual(HexCodec.bytes(from: "bb467f"), [0xBB, 0x46, 0x7F])
        XCTAssertNil(HexCodec.bytes(from: "ABC"))
    }

    func testLearnKeepsOppositeTurnOnSameController() {
        let right = GestureLearner.rule(
            for: .turnRight,
            message: MidiMessage(status: 0xBB, data1: 16, data2: 1),
            matchAnyValue: false
        )
        let left = GestureLearner.rule(
            for: .turnLeft,
            message: MidiMessage(status: 0xBB, data1: 16, data2: 127),
            matchAnyValue: false
        )
        let rules = GestureLearner.apply(left, to: GestureLearner.apply(right, to: []))
        XCTAssertEqual(Set(rules.map(\.gesture)), Set([.turnRight, .turnLeft]))
        let decoder = GestureDecoder(rules: rules)
        XCTAssertEqual(
            decoder.gesture(for: MidiMessage(status: 0xBB, data1: 16, data2: 1)),
            .turnRight
        )
        XCTAssertEqual(
            decoder.gesture(for: MidiMessage(status: 0xBB, data1: 16, data2: 127)),
            .turnLeft
        )
    }

    func testWildcardReplacesOtherRulesOnThatControl() {
        let exact = GestureRule(gesture: .turnLeft, status: 0xBB, data1: 16, data2: 127)
        let wildcard = GestureRule(gesture: .turnRight, status: 0xBB, data1: 16, data2: nil)
        let rules = GestureLearner.apply(wildcard, to: [exact])
        XCTAssertEqual(rules, [wildcard])
    }

    func testExactMatchBeatsWildcard() {
        let rules = [
            GestureRule(gesture: .turnRight, status: 0xB0, data1: 1, data2: nil),
            GestureRule(gesture: .press, status: 0xB0, data1: 1, data2: 127),
        ]
        let decoder = GestureDecoder(rules: rules)
        XCTAssertEqual(decoder.gesture(for: MidiMessage(status: 0xB0, data1: 1, data2: 127)), .press)
        XCTAssertEqual(decoder.gesture(for: MidiMessage(status: 0xB0, data1: 1, data2: 3)), .turnRight)
    }

    func testRouterIgnoresLedAndDebouncesPress() {
        var router = GestureRouter(
            rules: [
                GestureRule(gesture: .press, status: 0x90, data1: 60, data2: 127),
                GestureRule(gesture: .turnRight, status: 0xBB, data1: 70, data2: 10),
            ],
            pressCooldown: 0.2,
            turnCooldown: 0
        )
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(
            router.handle(MidiMessage(status: 0x90, data1: 60, data2: 127), at: start),
            .press
        )
        XCTAssertNil(
            router.handle(MidiMessage(status: 0x90, data1: 60, data2: 127), at: start.addingTimeInterval(0.05))
        )
        XCTAssertEqual(
            router.handle(MidiMessage(status: 0x90, data1: 60, data2: 127), at: start.addingTimeInterval(0.2)),
            .press
        )
        XCTAssertNil(router.handle(MidiMessage(status: 0xBB, data1: 70, data2: 10), at: start))
    }

    func testTurnsAreNotDebouncedByDefault() {
        var router = GestureRouter(
            rules: [GestureRule(gesture: .turnLeft, status: 0xBB, data1: 20, data2: 127)],
            turnCooldown: 0
        )
        let now = Date(timeIntervalSince1970: 50)
        XCTAssertEqual(router.handle(MidiMessage(status: 0xBB, data1: 20, data2: 127), at: now), .turnLeft)
        XCTAssertEqual(
            router.handle(MidiMessage(status: 0xBB, data1: 20, data2: 127), at: now.addingTimeInterval(0.001)),
            .turnLeft
        )
    }

    func testPortMatchPrefersSavedNameThenHint() {
        let ports = ["IAC Driver", "timeBuzzer", "USB MIDI"]
        XCTAssertEqual(PortMatch.choose(ports: ports, saved: "USB MIDI"), "USB MIDI")
        XCTAssertEqual(PortMatch.choose(ports: ports, saved: "Gone"), "timeBuzzer")
        XCTAssertEqual(PortMatch.choose(ports: ["Ideas In Logic"], saved: nil), "Ideas In Logic")
        XCTAssertNil(PortMatch.choose(ports: ["IAC Driver"], saved: nil))
    }

    func testConfigRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("buzzer-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(directory: directory)
        var config = AppConfig.default
        config.rules = [GestureRule(gesture: .press, status: 0x90, data1: 36, data2: 127)]
        config.bindings[0].actions = [
            .keystroke(key: "space", modifiers: [.command, .shift]),
            .shell("say done"),
            .openURL("https://example.com"),
            .setLED(hex: "00ff00"),
        ]
        try store.save(config)
        let loaded = store.load()
        XCTAssertEqual(loaded.rules, config.rules)
        XCTAssertEqual(loaded.actions(for: .press).count, 4)
        XCTAssertEqual(loaded.actions(for: .turnRight), [.media(.volumeUp)])
        XCTAssertEqual(loaded.connectColorHex, "FFB43C")
        try? FileManager.default.removeItem(at: directory)
    }

    func testBrokenConfigFallsBackToDefault() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("buzzer-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ConfigStore(directory: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), .default)
        try? FileManager.default.removeItem(at: directory)
    }

    func testKeyMapAliases() {
        XCTAssertEqual(KeyMap.virtualKey(for: " Space "), 0x31)
        XCTAssertEqual(KeyMap.virtualKey(for: "enter"), KeyMap.virtualKey(for: "return"))
        XCTAssertEqual(KeyMap.virtualKey(for: "left"), 0x7B)
        XCTAssertEqual(KeyMap.virtualKey(for: "f1"), 0x7A)
        XCTAssertNil(KeyMap.virtualKey(for: "not-a-key"))
    }

    func testActionSummaries() {
        XCTAssertEqual(
            BuzzerAction.keystroke(key: "space", modifiers: [.command]).summary,
            "⌘space"
        )
        XCTAssertEqual(BuzzerAction.media(.mute).summary, "Mute")
        XCTAssertEqual(BuzzerAction.setLED(hex: "#00ff00").summary, "LED #00FF00")
    }

    func testScriptedKnobSession() {
        let steps = KnobSimulation.run()
        XCTAssertEqual(steps.map(\.title).count, 9)

        XCTAssertEqual(steps[0].notices, [
            .learned(GestureRule(gesture: .press, status: 0x90, data1: 0x30, data2: 0x7F))
        ])
        XCTAssertEqual(steps[1].notices, [
            .learned(GestureRule(gesture: .turnRight, status: 0xBB, data1: 0x10, data2: 0x01))
        ])
        XCTAssertEqual(steps[2].notices, [
            .learned(GestureRule(gesture: .turnLeft, status: 0xBB, data1: 0x10, data2: 0x7F))
        ])
        XCTAssertTrue(steps[3].notices.isEmpty, "LED echo must not count as a gesture")
        XCTAssertEqual(steps[4].notices, [.performed(.press, [.media(.playPause)])])
        XCTAssertTrue(steps[5].notices.isEmpty, "Second press inside 180ms is ignored")
        XCTAssertEqual(steps[6].notices, [.performed(.press, [.media(.playPause)])])
        XCTAssertEqual(steps[7].notices, [
            .performed(.turnRight, [.media(.volumeUp)]),
            .performed(.turnRight, [.media(.volumeUp)]),
        ])
        XCTAssertEqual(steps[8].notices, [.performed(.turnLeft, [.media(.volumeDown)])])
        XCTAssertFalse(KnobSimulation.transcript().isEmpty)
    }

    func testCLILedAndParse() {
        XCTAssertEqual(BuzzerCLI.run(arguments: ["led", "FF0000", "0"]), 0)
        XCTAssertEqual(BuzzerCLI.run(arguments: ["led", "nope"]), 1)
        XCTAssertEqual(BuzzerCLI.run(arguments: ["parse", "F8", "90", "3C", "40"]), 0)
        XCTAssertEqual(BuzzerCLI.run(arguments: ["nope"]), 1)
    }
}
