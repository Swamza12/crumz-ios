import SwiftUI
import FirebaseCore

@main
struct CrumzApp: App {
    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            MainNavigationView()
                .preferredColorScheme(.light)
        }
    }
}
