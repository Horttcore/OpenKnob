#if os(macOS)
import AppKit
import BuzzerCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let learning = model.learning {
                learnBanner(learning)
            }
            if !model.accessibilityTrusted {
                accessibilityBanner
            }
            HSplitView {
                deviceColumn
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                gestureColumn
                    .frame(minWidth: 460)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            model.start()
            model.refreshAccessibility()
        }
    }

    private func learnBanner(_ gesture: KnobGesture) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
            Text(gesture.instruction)
                .font(.headline)
            Spacer()
            Button("Cancel") { model.cancelLearn() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(red: 0.96, green: 0.86, blue: 0.62))
        .foregroundStyle(Color(red: 0.28, green: 0.16, blue: 0.05))
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised")
            Text("Keystrokes and media keys need Accessibility permission for Buzzer.")
                .font(.callout)
            Spacer()
            Button("Allow") {
                Accessibility.prompt()
                model.refreshAccessibility()
            }
            Button("Settings") { Accessibility.openSettings() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var deviceColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Buzzer")
                        .font(.title2.weight(.semibold))
                    Text("Quit the official timeBuzzer app while you use this one, then teach press, turn right, and turn left.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                portCard
                colorCard
                logCard
            }
            .padding(18)
        }
    }

    private var portCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.statusMessage)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Picker("MIDI port", selection: Binding(
                get: { model.portSelection },
                set: { model.choosePort($0) }
            )) {
                Text("Automatic").tag("")
                ForEach(model.ports) { port in
                    Text(port.name).tag(port.name)
                }
            }
            .labelsHidden()
            Text(model.canPaint ? "LED output is open." : "LED output is not open yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Paint this color when the buzzer connects", isOn: Binding(
                get: { model.config.sendColorOnConnect },
                set: { model.setSendColorOnConnect($0) }
            ))
            .toggleStyle(.checkbox)
            Toggle("Open Buzzer at login", isOn: Binding(
                get: { model.config.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
        }
        .padding(12)
        .background(cardBackground)
    }

    private var colorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Light")
                .font(.headline)
            HStack(spacing: 10) {
                ColorPicker(
                    "Color",
                    selection: Binding(
                        get: { Color(buzzerHex: model.colorHex) ?? Color(red: 1, green: 0.71, blue: 0.24) },
                        set: { newColor in
                            if let hex = newColor.buzzerHex {
                                model.colorHex = hex
                                model.colorDraftChanged()
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
                TextField("FFB43C", text: $model.colorHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(maxWidth: 120)
                    .onSubmit { model.colorDraftChanged() }
                    .onChange(of: model.colorHex) { _ in
                        model.colorDraftChanged()
                    }
                Button("Send") { model.sendLED(hex: model.colorHex) }
            }
            HStack(spacing: 6) {
                swatch("Warm", "FFB43C")
                swatch("Red", "FF3B30")
                swatch("Green", "30D158")
                swatch("Blue", "0A84FF")
                swatch("Off", "000000")
            }
            Picker("Rings", selection: Binding(
                get: { model.paintAllRings ? -1 : model.ringIndex },
                set: { value in
                    if value < 0 {
                        model.setRing(all: true, index: model.ringIndex)
                    } else {
                        model.setRing(all: false, index: value)
                    }
                }
            )) {
                Text("All rings").tag(-1)
                Text("Ring 1").tag(0)
                Text("Ring 2").tag(1)
                Text("Ring 3").tag(2)
            }
            .pickerStyle(.segmented)
            Text("Three rings, MIDI channel 12, CC 70–78. Brightness is sent as 0–127.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(cardBackground)
    }

    private func swatch(_ name: String, _ hex: String) -> some View {
        Button(name) {
            model.colorHex = hex
            model.colorDraftChanged()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .tint(Color(buzzerHex: hex) ?? .accentColor)
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MIDI log")
                    .font(.headline)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.copyLog(), forType: .string)
                }
                .controlSize(.small)
            }
            if model.log.isEmpty {
                Text("Press or turn the knob. Incoming bytes show up here, including ones Buzzer does not understand yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.log.suffix(40)) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(line.date, format: .dateTime.hour().minute().second())
                                    .foregroundStyle(.secondary)
                                Text(line.text)
                                    .foregroundStyle(line.direction == .info ? Color.secondary : Color.primary)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 140, maxHeight: 220)
            }
            HStack {
                TextField("BB 10 01", text: $model.injectHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("As input") { model.inject() }
                Button("Send") { model.sendInjected() }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private var gestureColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Gestures")
                    .font(.title2.weight(.semibold))
                Text("Learn stores the next knob message that is not an LED update. Turn one click so left and right stay distinct.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("When learning, match any value on that control", isOn: $model.matchAnyValue)
                    .toggleStyle(.checkbox)
                    .disabled(model.learning != nil)
                ForEach(KnobGesture.allCases, id: \.self) { gesture in
                    GestureCard(gesture: gesture)
                }
                cooldownCard
            }
            .padding(18)
        }
    }

    private var cooldownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repeat guard")
                .font(.headline)
            HStack {
                Text("Press")
                TextField("180", value: Binding(
                    get: { model.config.pressCooldownMs },
                    set: { model.setCooldown(press: $0) }
                ), format: .number)
                .frame(width: 70)
                Text("ms")
                Spacer()
                Text("Turn")
                TextField("0", value: Binding(
                    get: { model.config.turnCooldownMs },
                    set: { model.setCooldown(turn: $0) }
                ), format: .number)
                .frame(width: 70)
                Text("ms")
            }
            .textFieldStyle(.roundedBorder)
            Text("Press ignores a second hit inside this window. Leave turn at 0 so fast spins keep firing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
    }
}

struct GestureCard: View {
    @EnvironmentObject private var model: AppModel
    let gesture: KnobGesture

    private var actions: [BuzzerAction] {
        model.config.actions(for: gesture)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture.title)
                        .font(.headline)
                    Text(model.config.rule(for: gesture)?.summary ?? "Not learned")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.config.rule(for: gesture) != nil {
                    Button("Forget") { model.clearRule(gesture) }
                        .controlSize(.small)
                }
                Button(model.learning == gesture ? "Listening…" : "Learn") {
                    model.beginLearn(gesture)
                }
                .disabled(model.learning != nil && model.learning != gesture)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.86, green: 0.42, blue: 0.12))
            }
            if actions.isEmpty {
                Text("No action yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(actions.indices, id: \.self) { index in
                ActionRow(gesture: gesture, index: index)
            }
            Menu {
                Button("Keystroke") { add(.keystroke(key: "space", modifiers: [])) }
                Button("Media key") { add(.media(defaultMedia)) }
                Button("LED color") { add(.setLED(hex: model.colorHex)) }
                Button("Shell command") { add(.shell("")) }
                Button("Open URL") { add(.openURL("https://")) }
            } label: {
                Label("Add action", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private var defaultMedia: MediaControl {
        switch gesture {
        case .press: return .playPause
        case .turnRight: return .volumeUp
        case .turnLeft: return .volumeDown
        }
    }

    private func add(_ action: BuzzerAction) {
        model.setActions(actions + [action], for: gesture)
    }
}

struct ActionRow: View {
    @EnvironmentObject private var model: AppModel
    let gesture: KnobGesture
    let index: Int

    private var action: BuzzerAction {
        let actions = model.config.actions(for: gesture)
        guard actions.indices.contains(index) else {
            return .media(.playPause)
        }
        return actions[index]
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Picker("Kind", selection: kindBinding) {
                Text("Key").tag(ActionKind.keystroke)
                Text("Media").tag(ActionKind.media)
                Text("LED").tag(ActionKind.led)
                Text("Shell").tag(ActionKind.shell)
                Text("URL").tag(ActionKind.url)
            }
            .labelsHidden()
            .frame(width: 90)
            editor
            Button {
                var actions = model.config.actions(for: gesture)
                guard actions.indices.contains(index) else { return }
                actions.remove(at: index)
                model.setActions(actions, for: gesture)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove action")
        }
    }

    @ViewBuilder
    private var editor: some View {
        switch action {
        case let .keystroke(key, modifiers):
            TextField("space", text: Binding(
                get: { key },
                set: { replace(.keystroke(key: $0, modifiers: modifiers)) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 120)
            ForEach(KeyModifier.allCases, id: \.self) { modifier in
                Toggle(modifier.symbol, isOn: Binding(
                    get: { modifiers.contains(modifier) },
                    set: { enabled in
                        var next = modifiers.filter { $0 != modifier }
                        if enabled { next.append(modifier) }
                        replace(.keystroke(key: key, modifiers: next))
                    }
                ))
                .toggleStyle(.button)
                .controlSize(.small)
            }
        case let .media(control):
            Picker("Media", selection: Binding(
                get: { control },
                set: { replace(.media($0)) }
            )) {
                ForEach(MediaControl.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .labelsHidden()
        case let .setLED(hex):
            TextField("FF8800", text: Binding(
                get: { hex },
                set: { replace(.setLED(hex: $0)) }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.body.monospaced())
        case let .shell(command):
            TextField("say finished", text: Binding(
                get: { command },
                set: { replace(.shell($0)) }
            ))
            .textFieldStyle(.roundedBorder)
        case let .openURL(url):
            TextField("https://", text: Binding(
                get: { url },
                set: { replace(.openURL($0)) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private var kindBinding: Binding<ActionKind> {
        Binding(
            get: { ActionKind(action) },
            set: { kind in
                guard kind != ActionKind(action) else { return }
                replace(kind.make(gesture: gesture, colorHex: model.colorHex))
            }
        )
    }

    private func replace(_ action: BuzzerAction) {
        var actions = model.config.actions(for: gesture)
        guard actions.indices.contains(index) else { return }
        actions[index] = action
        model.setActions(actions, for: gesture)
    }
}

enum ActionKind: String, Equatable {
    case keystroke
    case media
    case led
    case shell
    case url

    init(_ action: BuzzerAction) {
        switch action {
        case .keystroke: self = .keystroke
        case .media: self = .media
        case .setLED: self = .led
        case .shell: self = .shell
        case .openURL: self = .url
        }
    }

    func make(gesture: KnobGesture, colorHex: String) -> BuzzerAction {
        switch self {
        case .keystroke:
            return .keystroke(key: "space", modifiers: [])
        case .media:
            switch gesture {
            case .press: return .media(.playPause)
            case .turnRight: return .media(.volumeUp)
            case .turnLeft: return .media(.volumeDown)
            }
        case .led:
            return .setLED(hex: colorHex)
        case .shell:
            return .shell("")
        case .url:
            return .openURL("https://")
        }
    }
}

extension Color {
    init?(buzzerHex: String) {
        guard let rgb = LedProtocol.rgb(hex: buzzerHex) else { return nil }
        self.init(
            red: Double(rgb.r) / 255,
            green: Double(rgb.g) / 255,
            blue: Double(rgb.b) / 255
        )
    }

    var buzzerHex: String? {
        let resolved = NSColor(self).usingColorSpace(.sRGB)
        guard let resolved else { return nil }
        let red = UInt8(clamping: Int((resolved.redComponent * 255).rounded()))
        let green = UInt8(clamping: Int((resolved.greenComponent * 255).rounded()))
        let blue = UInt8(clamping: Int((resolved.blueComponent * 255).rounded()))
        return String(format: "%02X%02X%02X", red, green, blue)
    }
}
#endif
