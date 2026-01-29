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

    /// Sign a nonce to prove device identity
    func sign(nonce: String) -> String {
        guard let key = privateKey else { return "" }

        let data = Data(nonce.utf8)
        do {
            let signature = try key.signature(for: data)
            return signature.rawRepresentation.base64EncodedString()
        } catch {
            print("Failed to sign nonce: \(error)")
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
