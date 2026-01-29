import Foundation
import CryptoKit
import Security

/// Manages device identity using P-256 keypair stored in Keychain
class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let keychainService = "com.clawdbot.node"
    private let privateKeyTag = "com.clawdbot.node.privateKey"

    private var privateKey: P256.Signing.PrivateKey?

    var deviceId: String {
        return publicKeyFingerprint
    }

    var publicKeyBase64: String {
        guard let key = privateKey else { return "" }
        let publicKeyData = key.publicKey.rawRepresentation
        return publicKeyData.base64EncodedString()
    }

    private var publicKeyFingerprint: String {
        guard let key = privateKey else { return "" }
        let publicKeyData = key.publicKey.rawRepresentation
        let hash = SHA256.hash(data: publicKeyData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private init() {
        loadOrCreateKeyPair()
    }

    private func loadOrCreateKeyPair() {
        // Try to load existing key from Keychain
        if let keyData = loadPrivateKeyFromKeychain() {
            do {
                privateKey = try P256.Signing.PrivateKey(rawRepresentation: keyData)
                print("Loaded existing device identity: \(deviceId.prefix(16))...")
                return
            } catch {
                print("Failed to load private key: \(error)")
            }
        }

        // Create new keypair
        privateKey = P256.Signing.PrivateKey()
        if let key = privateKey {
            savePrivateKeyToKeychain(key.rawRepresentation)
            print("Created new device identity: \(deviceId.prefix(16))...")
        }
    }

    /// Build the device auth payload string that must be signed
    /// Format: version|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
    static func buildAuthPayload(
        deviceId: String,
        clientId: String,
        clientMode: String,
        role: String,
        scopes: [String],
        signedAtMs: Int64,
        token: String?,
        nonce: String
    ) -> String {
        let version = "v2"  // v2 includes nonce
        let scopesStr = scopes.joined(separator: ",")
        let tokenStr = token ?? ""

        return [version, deviceId, clientId, clientMode, role, scopesStr, String(signedAtMs), tokenStr, nonce].joined(separator: "|")
    }

    /// Sign the auth payload to prove device identity
    /// The gateway expects a DER-encoded ECDSA signature
    func sign(payload: String) -> String {
        guard let key = privateKey else { return "" }

        let data = Data(payload.utf8)
        do {
            let signature = try key.signature(for: data)
            // Return DER-encoded signature for compatibility with gateway
            return signature.derRepresentation.base64EncodedString()
        } catch {
            print("Failed to sign payload: \(error)")
            return ""
        }
    }

    // MARK: - Keychain Operations

    private func loadPrivateKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    private func savePrivateKeyToKeychain(_ keyData: Data) {
        // Delete any existing key
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: privateKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            print("Failed to save private key to Keychain: \(status)")
        }
    }
}

// MARK: - Device Token Storage
class DeviceTokenStorage {
    private static let tokenKey = "com.clawdbot.node.deviceToken"

    static var token: String? {
        get {
            UserDefaults.standard.string(forKey: tokenKey)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
        }
    }
}
