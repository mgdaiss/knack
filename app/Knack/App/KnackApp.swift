import AppKit
import SwiftUI

@main
struct KnackApp: App {
    @State private var model: AppModel

    init() {
        FontRegistration.registerBundledFonts()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Knack", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1024, minHeight: 680)
                .onOpenURL { model.handleURL($0) }
                .modifier(WindowActions(model: model))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .handlesExternalEvents(matching: ["*"])

        // Skills with their own window (Fridge Chef). Opened by ID, one window per skill.
        WindowGroup("Helper", id: "skill", for: String.self) { $skillID in
            if let skillID {
                SkillWindow(skillID: skillID)
                    .environment(model)
                    .modifier(WindowActions(model: model))
            }
        }
        .defaultSize(width: 1100, height: 760)
        .commands {
            ImportFromDevicesCommands()
        }

        MenuBarExtra {
            MenuBarContent().environment(model)
        } label: {
            Image(systemName: "face.smiling")
                .accessibilityLabel("Knack")
        }
    }
}

/// Hands SwiftUI's window actions to `AppModel` so hotkeys, ⌘K and the menu bar can open windows.
private struct WindowActions: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            model.openWindowAction = { id in openWindow(id: "skill", value: id) }
            model.openHomeAction = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

/// Menu bar extra (SPEC §8.5): installed helpers with hotkey hints, open Home, quit.
private struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.needsOnboarding {
            Button("Finish setting up Knack…") { openHome() }
        } else {
            ForEach(model.registry.active) { manifest in
                Button {
                    model.openWindowAction = model.openWindowAction ?? { id in openWindow(id: "skill", value: id) }
                    model.open(manifest.id)
                } label: {
                    if let hotkey = HotkeyService.display(for: manifest.id) {
                        Text("\(manifest.name)    \(hotkey)")
                    } else {
                        Text(manifest.name)
                    }
                }
            }
            if let balance = model.account?.balanceUSD {
                Divider()
                Text("Credit on us: \(Money.format(balance))")
            }
        }
        Divider()
        Button("Open Home") { openHome() }
            .keyboardShortcut("0", modifiers: .command)
        Button("Quit Knack") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }

    private func openHome() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
