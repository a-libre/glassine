import SwiftUI

/// Glassine on iPhone and iPad: the same root view over the same state as
/// the Mac's (Sources/Mac/App/GlassineApp.swift), in the one scene iOS gives
/// an app. The menus and the key monitor are the Mac's; what a keyboard
/// attached to an iPhone or iPad can do arrives here as the editor does.
@main
struct GlassineApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
    }
}
