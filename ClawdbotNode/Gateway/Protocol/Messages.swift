import Foundation

// MARK: - Message Types
enum MessageType: String, Codable {
    case req
    case res
    case event
}

// MARK: - Base Message
struct GatewayMessage: Codable {
    let type: MessageType
    let id: String?
    let method: String?
    let params: AnyCodable?
    let event: String?
    let payload: AnyCodable?
    let ok: Bool?
    let error: GatewayError?
    let seq: Int?
    let stateVersion: Int?
}

// MARK: - Gateway Error
struct GatewayError: Codable {
    let code: String
    let message: String
    let details: AnyCodable?
}

// MARK: - Connect Challenge
struct ConnectChallenge: Codable {
    let nonce: String
    let ts: Int64
}

// MARK: - Connect Request Params
struct ConnectParams: Codable {
    let minProtocol: Int
    let maxProtocol: Int
    let client: ClientInfo
    let role: String
    let scopes: [String]
    let caps: [String]
    let commands: [String]
    let permissions: [String: Bool]
    let auth: AuthInfo
    let locale: String
    let userAgent: String
    let device: DeviceInfo
}

struct ClientInfo: Codable {
    let id: String
    let version: String
    let platform: String
    let mode: String
}

struct AuthInfo: Codable {
    let token: String?
}

struct DeviceInfo: Codable {
    let id: String
    let publicKey: String
    let signature: String
    let signedAt: Int64
    let nonce: String
}

// MARK: - Hello OK Response
struct HelloOKPayload: Codable {
    let type: String
    let `protocol`: Int
    let policy: PolicyInfo
    let auth: HelloAuth
}

struct PolicyInfo: Codable {
    let tickIntervalMs: Int
}

struct HelloAuth: Codable {
    let deviceToken: String?
    let role: String
    let scopes: [String]
}

// MARK: - Node Invoke Request
struct NodeInvokeParams: Codable {
    let command: String
    let params: AnyCodable?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        params = try container.decodeIfPresent(AnyCodable.self, forKey: .params)
    }

    enum CodingKeys: String, CodingKey {
        case command
        case params
    }
}

// MARK: - AnyCodable Helper
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int64 as Int64:
            try container.encode(int64)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode value"))
        }
    }

    // Helper to extract dictionary
    var dictionary: [String: Any]? {
        return value as? [String: Any]
    }

    // Helper to extract string
    func string(forKey key: String) -> String? {
        guard let dict = dictionary else { return nil }
        return dict[key] as? String
    }

    // Helper to extract int
    func int(forKey key: String) -> Int? {
        guard let dict = dictionary else { return nil }
        return dict[key] as? Int
    }

    // Helper to extract double
    func double(forKey key: String) -> Double? {
        guard let dict = dictionary else { return nil }
        return dict[key] as? Double
    }

    // Helper to extract bool
    func bool(forKey key: String) -> Bool? {
        guard let dict = dictionary else { return nil }
        return dict[key] as? Bool
    }
}

// MARK: - Standard Error Codes
enum NodeErrorCode: String {
    case cameraDisabled = "CAMERA_DISABLED"
    case cameraPermissionRequired = "CAMERA_PERMISSION_REQUIRED"
    case recordAudioPermissionRequired = "RECORD_AUDIO_PERMISSION_REQUIRED"
    case nodeBackgroundUnavailable = "NODE_BACKGROUND_UNAVAILABLE"
    case locationDisabled = "LOCATION_DISABLED"
    case locationPermissionRequired = "LOCATION_PERMISSION_REQUIRED"
    case locationBackgroundUnavailable = "LOCATION_BACKGROUND_UNAVAILABLE"
    case locationTimeout = "LOCATION_TIMEOUT"
    case locationUnavailable = "LOCATION_UNAVAILABLE"
    case screenRecordingPermissionRequired = "SCREEN_RECORDING_PERMISSION_REQUIRED"
    case unknownCommand = "UNKNOWN_COMMAND"
    case invalidParams = "INVALID_PARAMS"
}

// MARK: - Request Builder
struct RequestBuilder {
    static func connect(
        deviceId: String,
        publicKey: String,
        signature: String,
        nonce: String,
        deviceToken: String?
    ) -> [String: Any] {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)

        // Build auth object - only include token if we have one
        var auth: [String: Any] = [:]
        if let token = deviceToken, !token.isEmpty {
            auth["token"] = token
        }

        return [
            "type": "req",
            "id": UUID().uuidString,
            "method": "connect",
            "params": [
                "minProtocol": 3,
                "maxProtocol": 3,
                "client": [
                    "id": "clawdbot-ios",
                    "version": "1.0.0",
                    "platform": "ios",
                    "mode": "node"
                ],
                "role": "node",
                "scopes": [] as [String],
                "caps": ["camera", "canvas", "screen", "location", "voice"],
                "commands": [
                    "camera.snap", "camera.clip", "camera.list",
                    "canvas.navigate", "canvas.snapshot", "canvas.eval", "canvas.present", "canvas.hide",
                    "screen.record",
                    "location.get"
                ],
                "permissions": AppSettings.shared.currentPermissions,
                "auth": auth,
                "locale": Locale.current.identifier,
                "userAgent": "clawdbot-ios/1.0.0",
                "device": [
                    "id": deviceId,
                    "publicKey": publicKey,
                    "signature": signature,
                    "signedAt": timestamp,
                    "nonce": nonce
                ]
            ] as [String: Any]
        ]
    }

    static func response(id: String, payload: [String: Any]) -> [String: Any] {
        return [
            "type": "res",
            "id": id,
            "ok": true,
            "payload": payload
        ]
    }

    static func errorResponse(id: String, code: NodeErrorCode, message: String) -> [String: Any] {
        return [
            "type": "res",
            "id": id,
            "ok": false,
            "error": [
                "code": code.rawValue,
                "message": message
            ]
        ]
    }
}
