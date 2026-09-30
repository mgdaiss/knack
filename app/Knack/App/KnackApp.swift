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
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
