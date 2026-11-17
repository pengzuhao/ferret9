import CryptoKit
import Foundation

enum Fingerprint {
    static func make(_ material: String) -> String {
        SHA256.hash(data: Data(material.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
    static func stamp() -> String { ISO8601DateFormatter().string(from: Date()) }
    static func containsSecret(_ text: String, secrets: [String]) -> Bool {
        secrets.contains { $0.count >= 6 && text.contains($0) }
    }
}
