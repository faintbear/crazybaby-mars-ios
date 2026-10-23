import SwiftUI

@main struct MarsControlApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = MarsController()
    var body: some Scene {
        WindowGroup {
            MarsInterface(controller: controller)
                .onChange(of: scenePhase, initial: true) { _, phase in
                    controller.setAppActive(phase == .active)
                }
        }
    }
}
