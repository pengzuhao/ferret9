import Foundation

public enum CofferPaths {
    public static let socket = "/var/run/ferret9.sock"
    public static let root = "/var/db/ferret9"
    public static let serviceUser = "_ferret9"
    public static let label = "com.ferret9.service"
    public static let right = "com.ferret9.manage"
    public static let version = "0.0.1"
}

public enum CofferError: Error, Equatable, LocalizedError {
    case invalid(String)
    case refused(String)
    case notFound(String)
    case exists(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let m): return m
        case .refused(let m): return m
        case .notFound(let m): return "未找到 \(m)"
        case .exists(let m): return "已存在 \(m)"
        case .unavailable(let m): return m
        }
    }
}

public enum ImportConfidence: String, Codable, Equatable { case high, medium, low }

public struct CredentialSummary: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name, kind, detail, fingerprint, added: String
    public var source: String?
    public init(name: String, kind: String, detail: String, fingerprint: String, added: String, source: String? = nil) {
        self.name = name; self.kind = kind; self.detail = detail; self.fingerprint = fingerprint; self.added = added
        self.source = source
    }
}

public struct ImportCandidate: Codable, Equatable, Identifiable {
    public var id: String { name }
    public var name, kind, detail, fingerprint, source: String
    public var confidence: ImportConfidence
    public init(name: String, kind: String, detail: String, fingerprint: String, source: String, confidence: ImportConfidence = .high) {
        self.name = name; self.kind = kind; self.detail = detail; self.fingerprint = fingerprint
        self.source = source; self.confidence = confidence
    }
}

public struct InspectReport: Codable, Equatable {
    public var encoding: String
    public var segmentCount: Int
    public var attempts, warnings: [String]
}

public enum Request: Codable, Equatable {
    case list
    case inspect(path: String)
    case inspectText(label: String, contentBase64: String)
    case add(name: String, source: String, origin: String?, authorization: String?)
    case addInline(name: String, label: String, contentBase64: String, origin: String?, overrideName: String?, overrideKind: String?, overrideDetail: String?, authorization: String?)
    case update(name: String, detail: String?, kind: String?, rename: String?, source: String?, authorization: String?)
    case updateInline(name: String, label: String, contentBase64: String, authorization: String?)
    case delete(name: String, authorization: String?)
    case test(name: String)
}

public struct Response: Codable, Equatable {
    public var ok: Bool
    public var message: String
    public var credentials: [CredentialSummary]
    public var candidates: [ImportCandidate]
    public var inspect: InspectReport?
    public init(ok: Bool, message: String, credentials: [CredentialSummary] = [], candidates: [ImportCandidate] = [], inspect: InspectReport? = nil) {
        self.ok = ok; self.message = message; self.credentials = credentials; self.candidates = candidates; self.inspect = inspect
    }
}

public enum Wire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T { try JSONDecoder().decode(type, from: data) }
}
