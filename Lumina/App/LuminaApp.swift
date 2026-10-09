import SwiftUI

@main
struct LuminaApp: App {
    @StateObject private var engine = CameraEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
