import SwiftUI

@main
struct TrackMetaApp: App {
    @State private var model = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(model: model)
        } label: {
            MenuBarLabel(snapshot: model.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
