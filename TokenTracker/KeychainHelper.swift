import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.tokentracker.apikeys"

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // Convenience accessors
    static var openAIKey: String? {
        get { load(key: "openai_admin_key") }
        set {
            if let v = newValue, !v.isEmpty { save(key: "openai_admin_key", value: v) }
            else { delete(key: "openai_admin_key") }
        }
    }

    static var anthropicKey: String? {
        get { load(key: "anthropic_admin_key") }
        set {
            if let v = newValue, !v.isEmpty { save(key: "anthropic_admin_key", value: v) }
            else { delete(key: "anthropic_admin_key") }
        }
    }

    // MARK: - AWS Bedrock

    static var awsAccessKeyId: String? {
        get { load(key: "aws_access_key_id") }
        set {
            if let v = newValue, !v.isEmpty { save(key: "aws_access_key_id", value: v) }
            else { delete(key: "aws_access_key_id") }
        }
    }

    static var awsSecretAccessKey: String? {
        get { load(key: "aws_secret_access_key") }
        set {
            if let v = newValue, !v.isEmpty { save(key: "aws_secret_access_key", value: v) }
            else { delete(key: "aws_secret_access_key") }
        }
    }

    static var awsSessionToken: String? {
        get { load(key: "aws_session_token") }
        set {
            if let v = newValue, !v.isEmpty { save(key: "aws_session_token", value: v) }
            else { delete(key: "aws_session_token") }
        }
    }
}
