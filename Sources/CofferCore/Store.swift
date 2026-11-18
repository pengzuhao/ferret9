import CryptoKit
import Foundation

public struct Store {
    public var directory: URL
    private let enc = JSONEncoder(), dec = JSONDecoder()
    public init(directory: URL) { self.directory = directory }

    public func list() throws -> [CredentialSummary] {
        try records().map(\.summary).sorted { $0.name < $1.name }
    }
    public func add(_ item: PreparedCredential, source: String? = nil) throws {
        try validate(item.name)
        let file = url(item.name)
        guard !FileManager.default.fileExists(atPath: file.path) else { throw CofferError.exists(item.name) }
        var rec = Record(item: item, added: Fingerprint.stamp())
        rec.source = source
        try write(rec, to: file)
    }
    public func update(name: String, detail: String?, kind: String?, rename: String?, item: PreparedCredential?) throws {
        try validate(name)
        var rec = try read(name)
        if let detail { rec.detail = detail }
        if let kind {
            guard kind.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,40}$", options: .regularExpression) != nil else {
                throw CofferError.invalid("类型格式无效")
            }
            rec.kind = kind
        }
        if let item {
            rec.kind = item.kind; rec.fingerprint = item.fingerprint; rec.payload = item.payload; rec.secrets = item.secrets
            if detail == nil { rec.detail = item.detail }
        }
        if let rename, rename != name {
            try validate(rename)
            let target = url(rename)
            guard !FileManager.default.fileExists(atPath: target.path) else { throw CofferError.exists(rename) }
            rec.name = rename
            try write(rec, to: target)
            try FileManager.default.removeItem(at: url(name))
            return
        }
        try write(rec, to: url(name))
    }
    public func delete(name: String) throws {
        try validate(name)
        let f = url(name)
        guard FileManager.default.fileExists(atPath: f.path) else { throw CofferError.notFound(name) }
        try FileManager.default.removeItem(at: f)
    }
    public func record(name: String) throws -> StoredCredential { try read(name).stored }
    public func secrets() throws -> [String] { try records().flatMap(\.secrets) }

    private func records() throws -> [Record] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .map { try dec.decode(Record.self, from: Data(contentsOf: $0)) }
    }
    private func read(_ name: String) throws -> Record {
        let f = url(name)
        guard FileManager.default.fileExists(atPath: f.path) else { throw CofferError.notFound(name) }
        return try dec.decode(Record.self, from: Data(contentsOf: f))
    }
    private func write(_ record: Record, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try enc.encode(record).write(to: file, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func url(_ name: String) -> URL { directory.appendingPathComponent(name).appendingPathExtension("json") }
    private func validate(_ name: String) throws {
        guard name.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$", options: .regularExpression) != nil else {
            throw CofferError.invalid("名称格式无效")
        }
    }
}

public struct StoredCredential {
    public var name, kind: String
    public var fields: [String: String]
    public var secrets: [String]
}

private struct Record: Codable {
    var name, kind, detail, fingerprint, added: String
    var source: String?
    var payload: Data
    var secrets: [String]
    init(item: PreparedCredential, added: String) {
        name = item.name; kind = item.kind; detail = item.detail; fingerprint = item.fingerprint
        self.added = added; payload = item.payload; secrets = item.secrets
    }
    var summary: CredentialSummary { CredentialSummary(name: name, kind: kind, detail: detail, fingerprint: fingerprint, added: added, source: source) }
    var stored: StoredCredential {
        let o = (try? JSONSerialization.jsonObject(with: payload)) as? [String: String] ?? [:]
        return StoredCredential(name: name, kind: kind, fields: o, secrets: secrets)
    }
}
