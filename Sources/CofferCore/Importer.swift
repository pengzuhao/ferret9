import CryptoKit
import Foundation

public struct PreparedCredential: Equatable {
    public var name, kind, detail, fingerprint: String
    public var payload: Data
    public var secrets: [String]
    public var confidence: ImportConfidence
    public func candidate(source: String) -> ImportCandidate {
        ImportCandidate(name: name, kind: kind, detail: detail, fingerprint: fingerprint, source: source, confidence: confidence)
    }
    public var candidate: ImportCandidate { candidate(source: "") }
}

public enum Importer {
    public struct ScanDiagnostics {
        public var encoding: String
        public var segmentCount: Int
        public var attempts, warnings: [String]
    }

    public static func analyze(data: Data, source: String) -> ([ImportCandidate], ScanDiagnostics) {
        let (items, diag) = prepare(data: data, source: source)
        return (items.map { $0.candidate(source: source) }, diag)
    }

    public static func prepare(data: Data, source: String) -> ([PreparedCredential], ScanDiagnostics) {
        var warnings: [String] = []
        var attempts = Set<String>()
        if Text.looksBinary(data) { warnings.append("内容含二进制字节") }
        guard let decoded = Text.decode(data) else {
            return ([], ScanDiagnostics(encoding: "unknown", segmentCount: 0, attempts: [], warnings: ["无法解码"]))
        }
        let base = baseName(from: source)
        if let whole = pem(decoded.text, base).first {
            return ([whole], ScanDiagnostics(encoding: decoded.encoding, segmentCount: 1, attempts: ["pem"], warnings: warnings))
        }
        let segments = Text.segments(decoded.text)
        if segments.count > 1 { attempts.insert("segment-split") }
        var found: [PreparedCredential] = []
        for (_, segment) in segments.enumerated() {
            found += scanBlock(data: Data(segment.utf8), text: segment, base: base, attempts: &attempts)
        }
        if found.isEmpty { found = scanBlock(data: data, text: decoded.text, base: base, attempts: &attempts) }
        return (unique(found), ScanDiagnostics(encoding: decoded.encoding, segmentCount: segments.count, attempts: attempts.sorted(), warnings: warnings))
    }

    public static func select(_ data: Data, source: String, name: String) throws -> PreparedCredential {
        let (items, _) = prepare(data: data, source: source)
        guard let item = items.first(where: { $0.name == name }) else { throw CofferError.notFound(name) }
        return item
    }

    private static func baseName(from source: String) -> String {
        var s = URL(fileURLWithPath: source).lastPathComponent
        while s.hasPrefix(".") { s.removeFirst() }
        let known = ["yaml", "yml", "json", "txt", "pem", "ini", "cfg", "conf"]
        if let dot = s.lastIndex(of: "."), dot != s.startIndex {
            let ext = String(s[s.index(after: dot)...]).lowercased()
            if known.contains(ext) { s = String(s[..<dot]) }
        }
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.replacingOccurrences(of: "@", with: "-at-")
        return s.isEmpty ? "clipboard" : s
    }

    private static func scanBlock(data: Data, text: String, base: String, attempts: inout Set<String>) -> [PreparedCredential] {
        let runs: [(String, () -> [PreparedCredential])] = [
            ("kubeconfig", { kube(text, base) }),
            ("aliyun-json", { aliyunJson(data, base) }),
            ("ini", { ini(data, base) }),
            ("assignments", { assignments(data, base) }),
            ("json", { jsonFlat(data, base) }),
            ("cloudflare-yaml", { cloudflare(text, base) }),
            ("feishu", { feishu(data, base) }),
            ("redis", { redis(text, base) }),
            ("pem", { pem(text, base) }),
            ("heuristic-tokens", { heuristicTokens(text, base) }),
        ]
        var found: [PreparedCredential] = []
        for (label, run) in runs {
            attempts.insert(label)
            found += run()
        }
        return found
    }

    private static func unique(_ items: [PreparedCredential]) -> [PreparedCredential] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.name).inserted }
    }

    private static func make(name: String, kind: String, detail: String, material: String,
                             payload: [String: String], secrets: [String], confidence: ImportConfidence = .high) -> PreparedCredential {
        let clean = payload.filter { !$0.value.isEmpty }
        let encoded = try! JSONSerialization.data(withJSONObject: clean, options: [.sortedKeys])
        return PreparedCredential(name: name, kind: kind, detail: detail, fingerprint: Fingerprint.make(material),
                                  payload: encoded, secrets: secrets, confidence: confidence)
    }

    private static func kube(_ text: String, _ base: String) -> [PreparedCredential] {
        guard text.contains("apiVersion:") && (text.contains("clusters:") || text.contains("kind: Config")) else { return [] }
        let current = Text.lines(text).compactMap { line -> String? in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("current-context:") else { return nil }
            let name = t.replacingOccurrences(of: "current-context:", with: "")
                .trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return name.isEmpty ? nil : name
        }.first ?? "default"
        let conf: ImportConfidence = text.contains("contexts:") ? .high : .medium
        let shown = current.count > 24 ? String(current.suffix(12)) : current
        return [make(name: base, kind: "kubeconfig", detail: "context \(shown)",
                     material: "kube\n\(current)\n\(text)", payload: ["format": "kubeconfig", "context": current, "document": text],
                     secrets: [], confidence: conf)]
    }

    private static func lookup(_ values: [String: String], _ name: String) -> String? {
        values.first { $0.key.caseInsensitiveCompare(name) == .orderedSame && !$0.value.isEmpty }?.value
    }

    private static func aliyunJson(_ data: Data, _ base: String) -> [PreparedCredential] {
        guard let parsed = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let docs: [[String: Any]]
        if let one = parsed as? [String: Any] {
            docs = [one]
        } else if let many = parsed as? [[String: Any]] {
            docs = many
        } else {
            return []
        }
        var found: [PreparedCredential] = []
        for (index, obj) in docs.enumerated() {
            guard let profiles = obj["profiles"] as? [[String: Any]], !profiles.isEmpty else { continue }
            let current = Text.field(obj, ["current"]) ?? ""
            let prefix = docs.count == 1 ? base : "\(base)-\(index + 1)"
            let items = profiles.compactMap { p -> PreparedCredential? in
                guard let key = Text.field(p, ["access_key_id"]), let secret = Text.field(p, ["access_key_secret"]) else { return nil }
                let pn = Text.field(p, ["name"]) ?? "default"
                let region = Text.field(p, ["region_id"]) ?? ""
                return make(name: "\(prefix)-\(pn)", kind: "aliyun", detail: region.isEmpty ? pn : "\(pn) \(region)",
                            material: key + ":" + secret,
                            payload: ["format": "aliyun", "profile": pn, "region": region, "access_key_id": key, "access_key_secret": secret],
                            secrets: [key, secret])
            }
            found += items.filter { current.isEmpty || profiles.count == 1 || $0.name.hasSuffix("-\(current)") }
        }
        return found
    }

    private static func ini(_ data: Data, _ base: String) -> [PreparedCredential] {
        Text.sections(data).compactMap { sec, v in
            if let k = lookup(v, "aws_access_key_id"), let s = lookup(v, "aws_secret_access_key") {
                return make(name: "\(base)-\(sec)", kind: "aws", detail: "profile \(sec)", material: k + ":" + s,
                            payload: ["format": "aws", "profile": sec, "access_key_id": k, "access_key_secret": s], secrets: [k, s])
            }
            if let k = lookup(v, "accessKeyID") ?? lookup(v, "access_key_id"), let s = lookup(v, "accessKeySecret") ?? lookup(v, "access_key_secret") {
                return make(name: "\(base)-\(sec)", kind: "ossutil", detail: v["endpoint"] ?? sec, material: k + ":" + s,
                            payload: ["format": "ossutil", "section": sec, "access_key_id": k, "access_key_secret": s], secrets: [k, s])
            }
            return nil
        }
    }

    private static func assignments(_ data: Data, _ base: String) -> [PreparedCredential] {
        let values = Text.assignments(data)
        let pairs = [
            ("ALIBABA_CLOUD_ACCESS_KEY_ID", "ALIBABA_CLOUD_ACCESS_KEY_SECRET", "aliyun"),
            ("ALICLOUD_ACCESS_KEY_ID", "ALICLOUD_ACCESS_KEY_SECRET", "aliyun"),
            ("ALICLOUD_ACCESS_KEY_ID_PUBLIC", "ALICLOUD_ACCESS_KEY_SECRET_PUBLIC", "aliyun"),
            ("ALICLOUD_ACCESS_KEY_ID_PRIVATE", "ALICLOUD_ACCESS_KEY_SECRET_PRIVATE", "aliyun"),
            ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "aws"),
        ]
        var found = pairs.compactMap { id, sec, kind -> PreparedCredential? in
            guard let k = values[id], let s = values[sec] else { return nil }
            let suf = id.replacingOccurrences(of: "_ACCESS_KEY_ID", with: "").lowercased()
            return make(name: "\(base)-\(suf)", kind: kind, detail: suf, material: k + ":" + s,
                        payload: ["format": kind, "access_key_id": k, "access_key_secret": s], secrets: [k, s])
        }
        for n in ["API_KEY", "TOKEN", "ACCESS_TOKEN", "token_value", "apikey", "api_key", "value"] {
            guard let v = lookup(values, n), v.count >= 8 else { continue }
            let label = (n == "value" ? values["name"] : nil) ?? n
            found.append(make(name: "\(base)-\(n.lowercased())", kind: "github", detail: label, material: n + ":" + v,
                              payload: ["format": "github", "field": n, "token": v], secrets: [v]))
        }
        return found
    }

    private static func jsonFlat(_ data: Data, _ base: String) -> [PreparedCredential] {
        guard let obj = Text.jsonObject(data), obj["profiles"] == nil else { return [] }
        if let k = Text.fieldDeep(obj, names: ["access_key_id"]), let s = Text.fieldDeep(obj, names: ["access_key_secret"]) {
            return [make(name: base, kind: "aliyun", detail: "json", material: k + ":" + s,
                         payload: ["format": "aliyun", "access_key_id": k, "access_key_secret": s], secrets: [k, s], confidence: .medium)]
        }
        return []
    }

    private static func cloudflare(_ text: String, _ base: String) -> [PreparedCredential] {
        guard text.contains("api-token") else { return [] }
        let records = Text.yamlListRecords(text, under: "accounts")
        return records.compactMap { r -> PreparedCredential? in
            guard let token = r["api-token"], token.count >= 8 else { return nil }
            let acct = (r["name"] ?? "default").replacingOccurrences(of: "@", with: "-at-")
            let label = r["api-token-name"] ?? ""
            return make(name: "\(base)-\(acct)", kind: "cloudflare",
                        detail: label.isEmpty ? "Cloudflare \(acct)" : "\(acct) · \(label)",
                        material: token,
                        payload: ["format": "cloudflare", "account": acct, "api_token": token, "api_token_name": label],
                        secrets: [token])
        }
    }

    private static func feishu(_ data: Data, _ base: String) -> [PreparedCredential] {
        guard let obj = Text.jsonObject(data), let secret = Text.field(obj, ["app_secret"]), secret.count >= 8 else { return [] }
        let app = Text.field(obj, ["app_id"]) ?? ""
        return [make(name: base, kind: "feishu", detail: app.isEmpty ? "飞书应用" : "飞书 \(app)",
                     material: secret, payload: ["format": "feishu", "app_id": app, "app_secret": secret], secrets: [secret])]
    }

    private static func redis(_ text: String, _ base: String) -> [PreparedCredential] {
        guard text.contains("password:") else { return [] }
        return Text.yamlMapRecords(text, under: "instances").compactMap { name, fields in
            guard let password = fields["password"], password.count >= 6 else { return nil }
            let host = fields["host"] ?? ""
            let region = fields["region"] ?? ""
            let detail = [name, region, host].filter { !$0.isEmpty }.joined(separator: " ")
            return make(name: "\(base)-\(name)", kind: "redis", detail: detail, material: name + ":" + password,
                        payload: ["format": "redis", "instance": name, "host": host, "region": region, "user": fields["user"] ?? "", "password": password],
                        secrets: [password])
        }
    }

    private static func pem(_ text: String, _ base: String) -> [PreparedCredential] {
        guard text.contains("-----BEGIN "), text.contains("PRIVATE KEY") else { return [] }
        return [make(name: base, kind: "private-key", detail: "pem", material: text, payload: ["format": "pem", "document": text], secrets: [])]
    }

    private static func heuristicTokens(_ text: String, _ base: String) -> [PreparedCredential] {
        let patterns: [(String, String)] = [
            (#"\bghp_[A-Za-z0-9]{20,}\b"#, "github"), (#"\bsk-[A-Za-z0-9]{20,}\b"#, "openai"),
        ]
        var found: [PreparedCredential] = [], idx = 0
        for (pat, label) in patterns {
            guard let tok = firstMatch(text, pat, 0) else { continue }
            idx += 1
            found.append(make(name: "\(base)-\(label)-\(idx)", kind: "github", detail: label, material: tok,
                              payload: ["format": "github", "token": tok, "vendor": label], secrets: [tok], confidence: .medium))
        }
        return found
    }

    private static func firstMatch(_ text: String, _ pattern: String, _ group: Int) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: text) else { return nil }
        return String(text[r])
    }
}
