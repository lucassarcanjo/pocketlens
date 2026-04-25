import SwiftUI

@main
struct PocketLensApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 500)
        }
        .windowResizability(.contentMinSize)
    }
}
