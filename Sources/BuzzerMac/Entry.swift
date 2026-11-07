import BuzzerCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if os(macOS)
import AppKit
import SwiftUI

@main
enum Entry {
    static func main() {
        if CommandLine.arguments.contains("--cli") {
            let code = BuzzerCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(code)
        }
        BuzzerMacApp.main()
    }
}

struct BuzzerMacApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(model)
        } label: {
            MenuLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Window("Buzzer", id: "main") {
            RootView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 640)
        .commands {
            CommandGroup(replacing: .appTermination) {
                Button("Quit Buzzer") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
#else
@main
enum Entry {
    static func main() {
        let code = BuzzerCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
        exit(code)
    }
}
#endif
