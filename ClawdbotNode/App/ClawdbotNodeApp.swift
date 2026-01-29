import SwiftUI

@main
struct ClawdbotNodeApp: App {
    @StateObject private var gatewayClient = GatewayClient.shared
    @StateObject private var appSettings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gatewayClient)
                .environmentObject(appSettings)
                .onAppear {
                    if appSettings.autoConnect {
                        gatewayClient.connect()
                    }
                }
        }
    }
}
