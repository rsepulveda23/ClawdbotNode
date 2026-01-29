import Foundation
import SwiftUI

/// Location mode options
enum LocationMode: String, CaseIterable {
    case off = "Off"
    case whileUsing = "While Using"
    case always = "Always"
}

/// App settings stored in UserDefaults
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let gatewayURL = "gatewayURL"
        static let autoConnect = "autoConnect"
        static let allowCamera = "allowCamera"
        static let locationMode = "locationMode"
        static let preciseLocation = "preciseLocation"
        static let allowScreenRecording = "allowScreenRecording"
        static let allowNotifications = "allowNotifications"
    }

    // MARK: - Default Gateway URL
    static let defaultGatewayURL = "ws://100.122.199.82:18789"

    // MARK: - Published Properties

    @Published var gatewayURL: String {
        didSet { defaults.set(gatewayURL, forKey: Keys.gatewayURL) }
    }

    @Published var autoConnect: Bool {
        didSet { defaults.set(autoConnect, forKey: Keys.autoConnect) }
    }

    @Published var allowCamera: Bool {
        didSet { defaults.set(allowCamera, forKey: Keys.allowCamera) }
    }

    @Published var locationMode: LocationMode {
        didSet { defaults.set(locationMode.rawValue, forKey: Keys.locationMode) }
    }

    @Published var preciseLocation: Bool {
        didSet { defaults.set(preciseLocation, forKey: Keys.preciseLocation) }
    }

    @Published var allowScreenRecording: Bool {
        didSet { defaults.set(allowScreenRecording, forKey: Keys.allowScreenRecording) }
    }

    @Published var allowNotifications: Bool {
        didSet { defaults.set(allowNotifications, forKey: Keys.allowNotifications) }
    }

    // MARK: - Computed Properties

    /// Current permissions map for connect request
    var currentPermissions: [String: Bool] {
        return [
            "camera.capture": allowCamera,
            "screen.record": allowScreenRecording,
            "location": locationMode != .off
        ]
    }

    // MARK: - Initialization

    private init() {
        // Load saved values or use defaults
        gatewayURL = defaults.string(forKey: Keys.gatewayURL) ?? Self.defaultGatewayURL
        autoConnect = defaults.bool(forKey: Keys.autoConnect)
        allowCamera = defaults.object(forKey: Keys.allowCamera) == nil ? true : defaults.bool(forKey: Keys.allowCamera)
        preciseLocation = defaults.bool(forKey: Keys.preciseLocation)
        allowScreenRecording = defaults.bool(forKey: Keys.allowScreenRecording)
        allowNotifications = defaults.bool(forKey: Keys.allowNotifications)

        // Location mode
        if let modeString = defaults.string(forKey: Keys.locationMode),
           let mode = LocationMode(rawValue: modeString) {
            locationMode = mode
        } else {
            locationMode = .off
        }
    }

    // MARK: - Reset

    func resetToDefaults() {
        gatewayURL = Self.defaultGatewayURL
        autoConnect = false
        allowCamera = true
        locationMode = .off
        preciseLocation = false
        allowScreenRecording = false
        allowNotifications = false
    }
}
