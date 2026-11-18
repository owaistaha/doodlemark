import SwiftUI

@main
struct DoodlemarkApp: App {
    var body: some Scene {
        WindowGroup {
            // Bootstrap step 1: a blank paper screen. The gallery replaces this in step 6.
            Theme.paper
                .ignoresSafeArea()
        }
    }
}
