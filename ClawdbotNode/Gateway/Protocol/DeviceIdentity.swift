import Foundation
import CryptoKit
import Security

/// Manages device identity using Ed25519 keypair stored in Keychain
/// The gateway uses Ed25519 for device authentication
class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let keychainService = "com.clawdbot.node"
    private let privateKeyTag = "com.clawdbot.node.ed25519.privateKey"

    private var privateKey: Curve25519.Signing.PrivateKey?

    var deviceId: String {
        return publicKeyFingerprint
    }

    /// Returns the raw 32-byte public key as base64url (no padding)
    var publicKeyBase64Url: String {
        guard let key = privateKey else { return "" }
        let publicKeyData = key.publicKey.rawRepresentation
        return base64UrlEncode(publicKeyData)
    }

    /// SHA256 hash of the raw public key bytes, hex encoded
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
                privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
                print("Loaded existing device identity: \(deviceId.prefix(16))...")
                return
            } catch {
                print("Failed to load private key: \(error)")
            }
        }

        // Create new Ed25519 keypair
        privateKey = Curve25519.Signing.PrivateKey()
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
    /// Returns base64url encoded Ed25519 signature (no padding)
    func sign(payload: String) -> String {
        guard let key = privateKey else { return "" }

        let data = Data(payload.utf8)
        do {
            let signature = try key.signature(for: data)
            // Return base64url encoded signature (gateway expects this format)
            return base64UrlEncode(signature)
        } catch {
            print("Failed to sign payload: \(error)")
            return ""
        }
    }

    // MARK: - Base64URL Encoding

    /// Encode data as base64url (no padding), as expected by the gateway
    private func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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

    /// Force regenerate the device identity (creates new keypair)
    func regenerateIdentity() {
        privateKey = Curve25519.Signing.PrivateKey()
        if let key = privateKey {
            savePrivateKeyToKeychain(key.rawRepresentation)
            print("Regenerated device identity: \(deviceId.prefix(16))...")
        }
        // Clear any stored device token since identity changed
        DeviceTokenStorage.token = nil
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
