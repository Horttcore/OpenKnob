#if os(macOS)
import CoreMIDI
import Foundation

struct MidiEndpointInfo: Equatable, Identifiable, Sendable {
    var id: Int32
    var name: String
}

final class MidiService: @unchecked Sendable {
    private let lock = NSLock()
    private var client = MIDIClientRef()
    private var inputPort = MIDIPortRef()
    private var outputPort = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private var destination = MIDIEndpointRef()
    private var connectedName: String?
    private var started = false
    private var onBytes: (([UInt8]) -> Void)?
    private var onSetup: (() -> Void)?

    func start(onBytes: @escaping ([UInt8]) -> Void, onSetup: @escaping () -> Void) -> String? {
        lock.lock()
        defer { lock.unlock() }
        self.onBytes = onBytes
        self.onSetup = onSetup
        guard !started else { return nil }

        var client = MIDIClientRef()
        let clientStatus = MIDIClientCreateWithBlock("Buzzer" as CFString, &client) { [weak self] _ in
            self?.onSetup?()
        }
        guard clientStatus == noErr else {
            return "MIDI client failed (\(clientStatus))."
        }
        self.client = client

        var input = MIDIPortRef()
        let inputStatus = MIDIInputPortCreateWithBlock(client, "Buzzer in" as CFString, &input) { [weak self] packetList, _ in
            self?.deliver(packetList)
        }
        guard inputStatus == noErr else {
            return "MIDI input failed (\(inputStatus))."
        }
        self.inputPort = input

        var output = MIDIPortRef()
        let outputStatus = MIDIOutputPortCreate(client, "Buzzer out" as CFString, &output)
        guard outputStatus == noErr else {
            return "MIDI output failed (\(outputStatus))."
        }
        self.outputPort = output
        started = true
        return nil
    }

    func sources() -> [MidiEndpointInfo] {
        lock.lock()
        defer { lock.unlock() }
        return (0..<MIDIGetNumberOfSources()).map { index in
            let endpoint = MIDIGetSource(index)
            return MidiEndpointInfo(id: Int32(index), name: displayName(endpoint))
        }
    }

    func connect(name: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard started else { return "MIDI is not running." }
        if connectedName == name, source != 0 {
            return nil
        }
        guard let match = endpoint(named: name, count: MIDIGetNumberOfSources(), getter: MIDIGetSource) else {
            return "No MIDI input named \(name)."
        }
        if source != 0 {
            MIDIPortDisconnectSource(inputPort, source)
        }
        let status = MIDIPortConnectSource(inputPort, match, nil)
        guard status == noErr else {
            source = 0
            connectedName = nil
            return "Could not listen to \(name) (\(status))."
        }
        source = match
        connectedName = name
        destination = endpoint(named: name, count: MIDIGetNumberOfDestinations(), getter: MIDIGetDestination) ?? 0
        if destination == 0 {
            return "Listening to \(name). No MIDI output with that name, so the LED cannot be set yet."
        }
        return nil
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        if source != 0 {
            MIDIPortDisconnectSource(inputPort, source)
        }
        source = 0
        destination = 0
        connectedName = nil
    }

    func currentSourceName() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return connectedName
    }

    func canSend() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return destination != 0
    }

    @discardableResult
    func send(_ bytes: [UInt8]) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard destination != 0 else { return "The buzzer has no MIDI output open." }
        guard !bytes.isEmpty else { return nil }
        var packetList = MIDIPacketList()
        let packet = MIDIPacketListInit(&packetList)
        let capacity = MemoryLayout<MIDIPacketList>.size
        let added: UnsafeMutablePointer<MIDIPacket>? = bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return nil }
            return MIDIPacketListAdd(&packetList, capacity, packet, 0, buffer.count, base)
        }
        guard added != nil else { return "Could not build a MIDI packet." }
        let status = MIDISend(outputPort, destination, &packetList)
        guard status == noErr else { return "MIDI send failed (\(status))." }
        return nil
    }

    private func deliver(_ packetList: UnsafePointer<MIDIPacketList>) {
        let packets = packets(from: packetList)
        guard !packets.isEmpty else { return }
        lock.lock()
        let callback = onBytes
        lock.unlock()
        for packet in packets {
            callback?(packet)
        }
    }

    private func packets(from packetList: UnsafePointer<MIDIPacketList>) -> [[UInt8]] {
        let count = Int(packetList.pointee.numPackets)
        guard count > 0, let offset = MemoryLayout.offset(of: \MIDIPacketList.packet) else { return [] }
        var pointer = UnsafeMutablePointer<MIDIPacket>(
            mutating: UnsafeRawPointer(packetList).advanced(by: offset).assumingMemoryBound(to: MIDIPacket.self)
        )
        var collected: [[UInt8]] = []
        collected.reserveCapacity(count)
        for _ in 0..<count {
            let length = Int(pointer.pointee.length)
            if length > 0 {
                let bytes = withUnsafeBytes(of: pointer.pointee.data) { raw in
                    Array(raw.prefix(length))
                }
                collected.append(bytes)
            }
            pointer = UnsafeMutablePointer(mutating: MIDIPacketNext(pointer))
        }
        return collected
    }

    private func endpoint(
        named name: String,
        count: Int,
        getter: (Int) -> MIDIEndpointRef
    ) -> MIDIEndpointRef? {
        for index in 0..<count {
            let endpoint = getter(index)
            if displayName(endpoint) == name {
                return endpoint
            }
        }
        return nil
    }

    private func displayName(_ object: MIDIObjectRef) -> String {
        var unmanaged: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &unmanaged)
        guard status == noErr, let unmanaged else { return "MIDI" }
        return unmanaged.takeRetainedValue() as String
    }

}
#endif
