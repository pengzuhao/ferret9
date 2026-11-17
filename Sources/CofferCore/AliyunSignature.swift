import CryptoKit
import Foundation

enum AliyunSignature {
    static func sign(method: String, parameters: [String: String], secret: String) -> String {
        let sorted = parameters.keys.sorted().map { "\(percentEncode($0))=\(percentEncode(parameters[$0]!))" }.joined(separator: "&")
        let string = "\(method)&%2F&\(percentEncode(sorted))"
        let key = SymmetricKey(data: Data((secret + "&").utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(string.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    static func url(endpoint: String, parameters: [String: String], secret: String) -> URL {
        var p = parameters
        p["SignatureMethod"] = "HMAC-SHA1"
        p["SignatureVersion"] = "1.0"
        p["SignatureNonce"] = UUID().uuidString
        p["Timestamp"] = ISO8601DateFormatter().string(from: Date())
        p["Format"] = "JSON"
        p["Signature"] = sign(method: "GET", parameters: p, secret: secret)
        let q = p.keys.sorted().map { "\($0)=\(percentEncode(p[$0]!))" }.joined(separator: "&")
        return URL(string: "https://\(endpoint)/?\(q)")!
    }

    private static func percentEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
