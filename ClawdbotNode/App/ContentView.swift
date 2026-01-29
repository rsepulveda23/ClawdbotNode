import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gatewayClient: GatewayClient
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Chat Tab
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)

            // Node Tab (original home view)
            NodeHomeView()
                .environmentObject(gatewayClient)
                .environmentObject(appSettings)
                .tabItem {
                    Label("Node", systemImage: "cpu.fill")
                }
                .tag(1)

            // Settings Tab
            SettingsView()
                .environmentObject(gatewayClient)
                .environmentObject(appSettings)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Auto-connect if enabled
            if appSettings.autoConnect && gatewayClient.connectionState == .disconnected {
                gatewayClient.connect()
            }
        }
    }
}

// MARK: - Node Home View (Original ContentView content)
struct NodeHomeView: View {
    @EnvironmentObject var gatewayClient: GatewayClient
    @EnvironmentObject var appSettings: AppSettings
    @State private var showCanvas = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.15),
                        Color(red: 0.1, green: 0.1, blue: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Main content
                    ScrollView {
                        VStack(spacing: 24) {
                            // Hero section
                            heroSection

                            // Connection card
                            connectionCard

                            // Capabilities grid
                            capabilitiesSection

                            // Activity log
                            activitySection
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 100)
                    }

                    Spacer(minLength: 0)
                }

                // Canvas overlay
                if showCanvas, let canvasURL = gatewayClient.canvasURL {
                    CanvasOverlay(
                        url: canvasURL,
                        frame: gatewayClient.canvasFrame,
                        isVisible: $showCanvas,
                        webView: gatewayClient.canvasWebView
                    )
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Clawdbot")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
        .onChange(of: gatewayClient.canvasVisible) { visible in
            withAnimation(.spring(response: 0.3)) {
                showCanvas = visible
            }
        }
    }

    // MARK: - Hero Section
    private var heroSection: some View {
        VStack(spacing: 16) {
            // Animated orb
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                statusColor.opacity(0.4),
                                statusColor.opacity(0.1),
                                .clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                    .blur(radius: 10)

                // Main orb
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                statusColor,
                                statusColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: statusColor.opacity(0.5), radius: 20)

                // Icon
                Image(systemName: statusIcon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(.white)
            }
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: gatewayClient.connectionState)

            // Status text
            Text(statusText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.vertical, 20)
    }

    // MARK: - Connection Card
    private var connectionCard: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gateway Connection")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))

                    Text(appSettings.gatewayURL)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                // Connection toggle
                Button {
                    if gatewayClient.connectionState == .connected {
                        gatewayClient.disconnect()
                    } else if gatewayClient.connectionState == .disconnected {
                        gatewayClient.connect()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if gatewayClient.connectionState == .connecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: gatewayClient.connectionState == .connected ? "stop.fill" : "play.fill")
                        }

                        Text(connectionButtonText)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(buttonGradient)
                    )
                }
                .disabled(gatewayClient.connectionState == .connecting)
            }

            // Device info
            if gatewayClient.connectionState == .connected {
                Divider()
                    .background(Color.white.opacity(0.1))

                HStack {
                    Label("Device ID", systemImage: "cpu")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))

                    Spacer()

                    Text(String(DeviceIdentity.shared.deviceId.prefix(16)) + "...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Capabilities Section
    private var capabilitiesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capabilities")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                CapabilityCard(
                    icon: "camera.fill",
                    title: "Camera",
                    subtitle: appSettings.allowCamera ? "Enabled" : "Disabled",
                    isEnabled: appSettings.allowCamera,
                    color: .blue
                )

                CapabilityCard(
                    icon: "location.fill",
                    title: "Location",
                    subtitle: appSettings.locationMode.rawValue,
                    isEnabled: appSettings.locationMode != .off,
                    color: .green
                )

                CapabilityCard(
                    icon: "rectangle.on.rectangle",
                    title: "Canvas",
                    subtitle: "WebView Ready",
                    isEnabled: true,
                    color: .purple
                )

                CapabilityCard(
                    icon: "record.circle",
                    title: "Screen",
                    subtitle: appSettings.allowScreenRecording ? "Enabled" : "Disabled",
                    isEnabled: appSettings.allowScreenRecording,
                    color: .red
                )
            }
        }
    }

    // MARK: - Activity Section
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Activity")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if !gatewayClient.activityLog.isEmpty {
                    Button("Clear") {
                        gatewayClient.clearActivityLog()
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                }
            }

            if gatewayClient.activityLog.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.2))
                        Text("No activity yet")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(.vertical, 30)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(gatewayClient.activityLog.suffix(5).reversed()) { entry in
                        ActivityRow(entry: entry)
                    }
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    // MARK: - Computed Properties
    private var statusColor: Color {
        switch gatewayClient.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusIcon: String {
        switch gatewayClient.connectionState {
        case .connected: return "checkmark"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .disconnected: return "power"
        case .error: return "exclamationmark.triangle"
        }
    }

    private var statusText: String {
        switch gatewayClient.connectionState {
        case .connected: return "Connected to Gateway"
        case .connecting: return "Connecting..."
        case .disconnected: return "Tap Connect to Start"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var connectionButtonText: String {
        switch gatewayClient.connectionState {
        case .connected: return "Disconnect"
        case .connecting: return "Connecting"
        case .disconnected, .error: return "Connect"
        }
    }

    private var buttonGradient: LinearGradient {
        switch gatewayClient.connectionState {
        case .connected:
            return LinearGradient(colors: [.red.opacity(0.8), .red.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
        case .connecting:
            return LinearGradient(colors: [.orange.opacity(0.8), .orange.opacity(0.6)], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
        }
    }
}

// MARK: - Capability Card
struct CapabilityCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let isEnabled: Bool
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(isEnabled ? color : .gray)

                Spacer()

                Circle()
                    .fill(isEnabled ? color : .gray.opacity(0.5))
                    .frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isEnabled ? color.opacity(0.3) : Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

// MARK: - Activity Row
struct ActivityRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 14))
                .foregroundColor(entry.color)
                .frame(width: 28, height: 28)
                .background(entry.color.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.command)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Text(entry.timestamp, style: .time)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(entry.success ? .green : .red)
                .font(.system(size: 16))
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Canvas Overlay
struct CanvasOverlay: View {
    let url: URL
    let frame: CGRect
    @Binding var isVisible: Bool
    let webView: CanvasWebView?

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    // Don't dismiss on tap
                }

            if let webView = webView {
                CanvasWebViewRepresentable(webView: webView)
                    .frame(width: frame.width > 0 ? frame.width : nil,
                           height: frame.height > 0 ? frame.height : 400)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.3), radius: 20)
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(GatewayClient.shared)
        .environmentObject(AppSettings.shared)
}
