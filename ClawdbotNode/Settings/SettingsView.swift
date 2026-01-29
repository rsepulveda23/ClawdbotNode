import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gatewayClient: GatewayClient
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showingResetAlert = false
    @State private var editedURL: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(red: 0.05, green: 0.05, blue: 0.1)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Connection Section
                        SettingsSection(title: "Connection", icon: "network") {
                            VStack(spacing: 16) {
                                // Gateway URL
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Gateway URL")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    TextField("ws://ip:port", text: $editedURL)
                                        .font(.system(size: 14, design: .monospaced))
                                        .padding(12)
                                        .background(Color.white.opacity(0.05))
                                        .cornerRadius(10)
                                        .foregroundColor(.white)
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)
                                        .onChange(of: editedURL) { newValue in
                                            appSettings.gatewayURL = newValue
                                        }
                                }

                                // Auto Connect Toggle
                                SettingsToggle(
                                    title: "Auto Connect",
                                    subtitle: "Connect when app launches",
                                    isOn: $appSettings.autoConnect
                                )

                                // Connection Status
                                HStack {
                                    Text("Status")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.6))

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(statusColor)
                                            .frame(width: 8, height: 8)
                                        Text(statusText)
                                            .font(.system(size: 13))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                            }
                        }

                        // Camera Section
                        SettingsSection(title: "Camera", icon: "camera.fill") {
                            SettingsToggle(
                                title: "Allow Camera",
                                subtitle: "Take photos and videos when requested",
                                isOn: $appSettings.allowCamera
                            )
                        }

                        // Location Section
                        SettingsSection(title: "Location", icon: "location.fill") {
                            VStack(spacing: 16) {
                                // Location Mode Picker
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Location Access")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    Picker("Location Mode", selection: $appSettings.locationMode) {
                                        ForEach(LocationMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .tint(.blue)
                                }

                                // Precise Location Toggle
                                if appSettings.locationMode != .off {
                                    SettingsToggle(
                                        title: "Precise Location",
                                        subtitle: "Use exact GPS coordinates",
                                        isOn: $appSettings.preciseLocation
                                    )
                                }
                            }
                        }

                        // Screen Recording Section
                        SettingsSection(title: "Screen Recording", icon: "record.circle") {
                            SettingsToggle(
                                title: "Allow Screen Recording",
                                subtitle: "Record screen content when requested",
                                isOn: $appSettings.allowScreenRecording
                            )
                        }

                        // Notifications Section
                        SettingsSection(title: "Notifications", icon: "bell.fill") {
                            SettingsToggle(
                                title: "Allow Notifications",
                                subtitle: "Receive alerts from your AI assistant",
                                isOn: $appSettings.allowNotifications
                            )
                        }

                        // Device Info Section
                        SettingsSection(title: "Device Info", icon: "cpu") {
                            VStack(spacing: 12) {
                                SettingsInfoRow(
                                    label: "Device ID",
                                    value: String(DeviceIdentity.shared.deviceId.prefix(20)) + "..."
                                )

                                if let token = DeviceTokenStorage.token {
                                    SettingsInfoRow(
                                        label: "Device Token",
                                        value: String(token.prefix(20)) + "..."
                                    )
                                }

                                SettingsInfoRow(
                                    label: "App Version",
                                    value: "1.0.0"
                                )
                            }
                        }

                        // Reset Section
                        Button {
                            showingResetAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Defaults")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.blue)
                }
            }
            .alert("Reset Settings", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    appSettings.resetToDefaults()
                    editedURL = appSettings.gatewayURL
                }
            } message: {
                Text("Are you sure you want to reset all settings to their defaults?")
            }
            .onAppear {
                editedURL = appSettings.gatewayURL
            }
        }
        .preferredColorScheme(.dark)
    }

    private var statusColor: Color {
        switch gatewayClient.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch gatewayClient.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting..."
        case .disconnected: return "Disconnected"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.blue)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// MARK: - Settings Toggle
struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .tint(.blue)
    }
}

// MARK: - Settings Info Row
struct SettingsInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(GatewayClient.shared)
        .environmentObject(AppSettings.shared)
}
