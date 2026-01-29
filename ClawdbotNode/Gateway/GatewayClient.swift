import Foundation
import SwiftUI
import Combine

// MARK: - Connection State
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected): return true
        case (.connecting, .connecting): return true
        case (.connected, .connected): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Activity Log Entry
struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let command: String
    let success: Bool
    let icon: String
    let color: Color
}

// MARK: - Gateway Client
@MainActor
class GatewayClient: ObservableObject {
    static let shared = GatewayClient()

    @Published var connectionState: ConnectionState = .disconnected
    @Published var activityLog: [ActivityLogEntry] = []
    @Published var canvasVisible = false
    @Published var canvasURL: URL?
    @Published var canvasFrame: CGRect = .zero
    @Published var canvasWebView: CanvasWebView?

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var challengeNonce: String?
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 10
    private var reconnectTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?

    private let cameraCapability = CameraCapability()
    private let locationCapability = LocationCapability()
    private let screenRecordCapability = ScreenRecordCapability()

    private init() {
        session = URLSession(configuration: .default)
        canvasWebView = CanvasWebView()
    }

    // MARK: - Connection Management

    func connect() {
        guard connectionState != .connected && connectionState != .connecting else { return }

        let urlString = AppSettings.shared.gatewayURL
        guard let url = URL(string: urlString) else {
            connectionState = .error("Invalid gateway URL")
            return
        }

        connectionState = .connecting
        print("Connecting to gateway: \(urlString)")

        webSocketTask = session?.webSocketTask(with: url)
        webSocketTask?.resume()

        receiveMessages()
    }

    func disconnect() {
        reconnectTask?.cancel()
        pingTask?.cancel()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        connectionState = .disconnected
        print("Disconnected from gateway")
    }

    func clearActivityLog() {
        activityLog.removeAll()
    }

    // MARK: - Message Handling

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    // Continue receiving
                    self.receiveMessages()

                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.handleDisconnection()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let json = json, let type = json["type"] as? String else { return }

            switch type {
            case "event":
                handleEvent(json)
            case "req":
                handleRequest(json)
            case "res":
                handleResponse(json)
            default:
                print("Unknown message type: \(type)")
            }
        } catch {
            print("Failed to parse message: \(error)")
        }
    }

    private func handleEvent(_ json: [String: Any]) {
        guard let eventName = json["event"] as? String else { return }

        switch eventName {
        case "connect.challenge":
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String {
                challengeNonce = nonce
                sendConnectRequest(nonce: nonce)
            }
        default:
            print("Unhandled event: \(eventName)")
        }
    }

    private func handleRequest(_ json: [String: Any]) {
        guard let id = json["id"] as? String,
              let method = json["method"] as? String else { return }

        switch method {
        case "node.invoke":
            if let params = json["params"] as? [String: Any],
               let command = params["command"] as? String {
                let commandParams = params["params"] as? [String: Any]
                handleNodeInvoke(requestId: id, command: command, params: commandParams)
            }
        default:
            print("Unknown request method: \(method)")
            sendError(requestId: id, code: .unknownCommand, message: "Unknown method: \(method)")
        }
    }

    private func handleResponse(_ json: [String: Any]) {
        guard let ok = json["ok"] as? Bool else { return }

        if ok {
            if let payload = json["payload"] as? [String: Any],
               let type = payload["type"] as? String,
               type == "hello-ok" {
                handleHelloOK(payload)
            }
        } else {
            if let error = json["error"] as? [String: Any] {
                let code = error["code"] as? String ?? "UNKNOWN"
                let message = error["message"] as? String ?? "Unknown error"
                print("Gateway error: \(code) - \(message)")
                connectionState = .error(message)
            }
        }
    }

    private func handleHelloOK(_ payload: [String: Any]) {
        connectionState = .connected
        reconnectAttempts = 0

        // Extract and store device token
        if let auth = payload["auth"] as? [String: Any],
           let token = auth["deviceToken"] as? String {
            DeviceTokenStorage.token = token
            print("Device token saved")
        }

        // Start keepalive
        if let policy = payload["policy"] as? [String: Any],
           let tickInterval = policy["tickIntervalMs"] as? Int {
            startKeepalive(interval: TimeInterval(tickInterval) / 1000.0)
        }

        print("Connected to gateway successfully")
        logActivity(command: "Connected", success: true, icon: "checkmark.circle", color: .green)
    }

    // MARK: - Node Invoke Handler

    private func handleNodeInvoke(requestId: String, command: String, params: [String: Any]?) {
        print("Received command: \(command)")

        // Check if app is in foreground for commands that require it
        let foregroundCommands = ["camera.snap", "camera.clip", "canvas.present", "canvas.navigate",
                                  "canvas.eval", "canvas.snapshot", "screen.record"]
        if foregroundCommands.contains(command) {
            if UIApplication.shared.applicationState != .active {
                sendError(requestId: requestId, code: .nodeBackgroundUnavailable,
                         message: "This command requires the app to be in the foreground")
                logActivity(command: command, success: false, icon: "moon.fill", color: .orange)
                return
            }
        }

        Task {
            do {
                let response = try await executeCommand(command: command, params: params)
                sendResponse(requestId: requestId, payload: response)
                logActivity(command: command, success: true, icon: iconForCommand(command), color: colorForCommand(command))
            } catch let error as NodeError {
                sendError(requestId: requestId, code: error.code, message: error.message)
                logActivity(command: command, success: false, icon: iconForCommand(command), color: .red)
            } catch {
                sendError(requestId: requestId, code: .unknownCommand, message: error.localizedDescription)
                logActivity(command: command, success: false, icon: iconForCommand(command), color: .red)
            }
        }
    }

    private func executeCommand(command: String, params: [String: Any]?) async throws -> [String: Any] {
        switch command {
        // Camera commands
        case "camera.list":
            return try await cameraCapability.listCameras()

        case "camera.snap":
            let facing = params?["facing"] as? String ?? "back"
            let maxWidth = params?["maxWidth"] as? Int ?? 1600
            let quality = params?["quality"] as? Double ?? 0.9
            let format = params?["format"] as? String ?? "jpg"
            let delayMs = params?["delayMs"] as? Int ?? 0
            return try await cameraCapability.snap(
                facing: facing, maxWidth: maxWidth, quality: quality,
                format: format, delayMs: delayMs
            )

        case "camera.clip":
            let facing = params?["facing"] as? String ?? "back"
            let durationMs = min(params?["durationMs"] as? Int ?? 3000, 60000) // Max 60 seconds
            let includeAudio = params?["includeAudio"] as? Bool ?? true
            let format = params?["format"] as? String ?? "mp4"
            return try await cameraCapability.clip(
                facing: facing, durationMs: durationMs, includeAudio: includeAudio, format: format
            )

        // Canvas commands
        case "canvas.present":
            let target = params?["target"] as? String ?? ""
            let x = params?["x"] as? CGFloat ?? 0
            let y = params?["y"] as? CGFloat ?? 0
            let width = params?["width"] as? CGFloat ?? UIScreen.main.bounds.width
            let height = params?["height"] as? CGFloat ?? 400
            return await presentCanvas(target: target, frame: CGRect(x: x, y: y, width: width, height: height))

        case "canvas.hide":
            return await hideCanvas()

        case "canvas.navigate":
            guard let url = params?["url"] as? String else {
                throw NodeError(code: .invalidParams, message: "URL required")
            }
            return await navigateCanvas(url: url)

        case "canvas.eval":
            guard let js = params?["javaScript"] as? String else {
                throw NodeError(code: .invalidParams, message: "javaScript required")
            }
            return try await evalCanvas(js: js)

        case "canvas.snapshot":
            let format = params?["format"] as? String ?? "png"
            let maxWidth = params?["maxWidth"] as? Int ?? 1200
            let quality = params?["quality"] as? Double ?? 0.9
            return try await snapshotCanvas(format: format, maxWidth: maxWidth, quality: quality)

        // Location commands
        case "location.get":
            let timeoutMs = params?["timeoutMs"] as? Int ?? 10000
            let maxAgeMs = params?["maxAgeMs"] as? Int ?? 15000
            let accuracy = params?["desiredAccuracy"] as? String ?? "balanced"
            return try await locationCapability.getLocation(
                timeoutMs: timeoutMs, maxAgeMs: maxAgeMs, desiredAccuracy: accuracy
            )

        // Screen recording commands
        case "screen.record":
            let durationMs = min(params?["durationMs"] as? Int ?? 10000, 60000) // Max 60 seconds
            let fps = params?["fps"] as? Int ?? 10
            let includeAudio = params?["includeAudio"] as? Bool ?? false
            return try await screenRecordCapability.record(
                durationMs: durationMs, fps: fps, includeAudio: includeAudio
            )

        default:
            throw NodeError(code: .unknownCommand, message: "Unknown command: \(command)")
        }
    }

    // MARK: - Canvas Methods

    private func presentCanvas(target: String, frame: CGRect) async -> [String: Any] {
        if let url = URL(string: target) {
            canvasURL = url
            canvasFrame = frame
            canvasWebView?.load(url: url)
            canvasVisible = true
        }
        return ["success": true]
    }

    private func hideCanvas() async -> [String: Any] {
        canvasVisible = false
        canvasURL = nil
        return ["success": true]
    }

    private func navigateCanvas(url: String) async -> [String: Any] {
        if let webView = canvasWebView, let url = URL(string: url) {
            webView.load(url: url)
            canvasURL = url
        }
        return ["success": true]
    }

    private func evalCanvas(js: String) async throws -> [String: Any] {
        guard let webView = canvasWebView else {
            throw NodeError(code: .invalidParams, message: "Canvas not initialized")
        }
        let result = await webView.evaluateJavaScript(js)
        return ["result": result ?? NSNull()]
    }

    private func snapshotCanvas(format: String, maxWidth: Int, quality: Double) async throws -> [String: Any] {
        guard let webView = canvasWebView else {
            throw NodeError(code: .invalidParams, message: "Canvas not initialized")
        }
        let imageData = await webView.snapshot(format: format, maxWidth: maxWidth, quality: quality)
        guard let data = imageData else {
            throw NodeError(code: .invalidParams, message: "Failed to capture canvas")
        }
        return [
            "format": format,
            "base64": data.base64EncodedString()
        ]
    }

    // MARK: - Sending Messages

    private func sendConnectRequest(nonce: String) {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let deviceId = DeviceIdentity.shared.deviceId
        let token = DeviceTokenStorage.token

        // Build the auth payload that needs to be signed
        // Format: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
        let authPayload = DeviceIdentity.buildAuthPayload(
            deviceId: deviceId,
            clientId: "clawdbot-ios",
            clientMode: "node",
            role: "node",
            scopes: [],
            signedAtMs: timestamp,
            token: token,
            nonce: nonce
        )

        let signature = DeviceIdentity.shared.sign(payload: authPayload)

        let request = RequestBuilder.connect(
            deviceId: deviceId,
            publicKey: DeviceIdentity.shared.publicKeyBase64,
            signature: signature,
            nonce: nonce,
            signedAt: timestamp,
            deviceToken: token
        )
        sendMessage(request)
    }

    private func sendResponse(requestId: String, payload: [String: Any]) {
        let response = RequestBuilder.response(id: requestId, payload: payload)
        sendMessage(response)
    }

    private func sendError(requestId: String, code: NodeErrorCode, message: String) {
        let response = RequestBuilder.errorResponse(id: requestId, code: code, message: message)
        sendMessage(response)
    }

    private func sendMessage(_ dict: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            if let text = String(data: data, encoding: .utf8) {
                webSocketTask?.send(.string(text)) { error in
                    if let error = error {
                        print("Send error: \(error)")
                    }
                }
            }
        } catch {
            print("Failed to serialize message: \(error)")
        }
    }

    // MARK: - Keepalive

    private func startKeepalive(interval: TimeInterval) {
        pingTask?.cancel()
        pingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                webSocketTask?.sendPing { error in
                    if let error = error {
                        print("Ping failed: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Reconnection

    private func handleDisconnection() {
        guard connectionState == .connected || connectionState == .connecting else { return }
        connectionState = .disconnected

        if reconnectAttempts < maxReconnectAttempts {
            reconnectTask = Task {
                let delay = min(pow(2.0, Double(reconnectAttempts)), 30.0) // Exponential backoff, max 30s
                print("Reconnecting in \(delay) seconds...")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                if !Task.isCancelled {
                    reconnectAttempts += 1
                    connect()
                }
            }
        } else {
            connectionState = .error("Max reconnection attempts reached")
        }
    }

    // MARK: - Activity Logging

    private func logActivity(command: String, success: Bool, icon: String, color: Color) {
        let entry = ActivityLogEntry(
            timestamp: Date(),
            command: command,
            success: success,
            icon: icon,
            color: color
        )
        activityLog.append(entry)

        // Keep only last 50 entries
        if activityLog.count > 50 {
            activityLog.removeFirst(activityLog.count - 50)
        }
    }

    private func iconForCommand(_ command: String) -> String {
        if command.hasPrefix("camera") { return "camera.fill" }
        if command.hasPrefix("canvas") { return "rectangle.on.rectangle" }
        if command.hasPrefix("location") { return "location.fill" }
        if command.hasPrefix("screen") { return "record.circle" }
        return "bolt.fill"
    }

    private func colorForCommand(_ command: String) -> Color {
        if command.hasPrefix("camera") { return .blue }
        if command.hasPrefix("canvas") { return .purple }
        if command.hasPrefix("location") { return .green }
        if command.hasPrefix("screen") { return .red }
        return .orange
    }
}

// MARK: - Node Error
struct NodeError: Error {
    let code: NodeErrorCode
    let message: String
}
