import CoreLocation
import UIKit

/// Handles location services for the Clawdbot node
class LocationCapability: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var lastLocation: CLLocation?
    private var lastLocationTime: Date?

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func getLocation(timeoutMs: Int, maxAgeMs: Int, desiredAccuracy: String) async throws -> [String: Any] {
        // Check if location is enabled in settings
        guard AppSettings.shared.locationMode != .off else {
            throw NodeError(code: .locationDisabled, message: "Location is disabled in app settings")
        }

        // Check system permission
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            // Request permission
            if AppSettings.shared.locationMode == .always {
                locationManager.requestAlwaysAuthorization()
            } else {
                locationManager.requestWhenInUseAuthorization()
            }
            // Wait a moment for permission dialog
            try await Task.sleep(nanoseconds: 500_000_000)

        case .restricted, .denied:
            throw NodeError(code: .locationPermissionRequired, message: "Location permission not granted")

        case .authorizedWhenInUse:
            // Check if app is in background
            if await UIApplication.shared.applicationState != .active {
                throw NodeError(code: .locationBackgroundUnavailable,
                               message: "App must be in foreground for 'when in use' location permission")
            }

        case .authorizedAlways:
            // Good to go
            break

        @unknown default:
            throw NodeError(code: .locationPermissionRequired, message: "Unknown location authorization status")
        }

        // Check for cached location
        if let cached = lastLocation,
           let cachedTime = lastLocationTime,
           Date().timeIntervalSince(cachedTime) * 1000 < Double(maxAgeMs) {
            return formatLocation(cached, isPrecise: AppSettings.shared.preciseLocation)
        }

        // Set accuracy based on parameter and settings
        let accuracy: CLLocationAccuracy
        switch desiredAccuracy {
        case "coarse":
            accuracy = kCLLocationAccuracyKilometer
        case "precise":
            accuracy = AppSettings.shared.preciseLocation ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        default: // "balanced"
            accuracy = AppSettings.shared.preciseLocation ? kCLLocationAccuracyNearestTenMeters : kCLLocationAccuracyHundredMeters
        }
        locationManager.desiredAccuracy = accuracy

        // Request location with timeout
        return try await withThrowingTaskGroup(of: [String: Any].self) { group in
            group.addTask {
                let location = try await self.requestLocation()
                return self.formatLocation(location, isPrecise: AppSettings.shared.preciseLocation)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                throw NodeError(code: .locationTimeout, message: "Location request timed out")
            }

            // Return first successful result or throw first error
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func requestLocation() async throws -> CLLocation {
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            locationManager.requestLocation()
        }
    }

    private func formatLocation(_ location: CLLocation, isPrecise: Bool) -> [String: Any] {
        lastLocation = location
        lastLocationTime = Date()

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        return [
            "lat": location.coordinate.latitude,
            "lon": location.coordinate.longitude,
            "accuracyMeters": location.horizontalAccuracy,
            "altitudeMeters": location.altitude,
            "speedMps": max(0, location.speed),
            "headingDeg": max(0, location.course),
            "timestamp": dateFormatter.string(from: location.timestamp),
            "isPrecise": isPrecise,
            "source": location.horizontalAccuracy < 10 ? "gps" : "network"
        ]
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                locationContinuation?.resume(throwing: NodeError(code: .locationPermissionRequired, message: "Location permission denied"))
            case .locationUnknown:
                locationContinuation?.resume(throwing: NodeError(code: .locationUnavailable, message: "Location unavailable"))
            default:
                locationContinuation?.resume(throwing: NodeError(code: .locationUnavailable, message: error.localizedDescription))
            }
        } else {
            locationContinuation?.resume(throwing: NodeError(code: .locationUnavailable, message: error.localizedDescription))
        }
        locationContinuation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Handle authorization changes if needed
    }
}
