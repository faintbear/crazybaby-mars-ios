import SwiftUI

@main struct MarsControlApp: App {
    @StateObject private var controller = MarsController()
    var body: some Scene {
        WindowGroup { MarsInterface(controller: controller) }
    }
}
