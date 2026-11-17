import Foundation

enum Text {
    static func decode(_ data: Data) -> (text: String, encoding: String)? {
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        for (enc, name) in [(String.Encoding.utf8, "utf-8"), (gb, "gb18030"), (.isoLatin1, "latin-1")] as [(String.Encoding, String)] {
            if let t = String(data: data, encoding: enc), !t.isEmpty {
                var c = t; if c.hasPrefix("\u{FEFF}") { c.removeFirst() }; return (c, name)
            }
        }
        return nil
    }
    static func lines(_ text: String) -> [String] { text.components(separatedBy: .newlines) }
    static func lines(_ data: Data) -> [String] { decode(data).map { lines($0.text) } ?? [] }
    static func unquote(_ raw: String) -> String {
        let v = raw.trimmingCharacters(in: .whitespaces)
        guard v.count >= 2, let first = v.first, let last = v.last, first == last, first == "\"" || first == "'" else { return v }
        return String(v.dropFirst().dropLast())
    }
    static func segments(_ text: String) -> [String] {
        var blocks: [String] = [], cur: [String] = []
        for raw in lines(text) {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t == "---" { if !cur.isEmpty { blocks.append(cur.joined(separator: "\n")); cur = [] }; continue }
            cur.append(raw)
        }
        if !cur.isEmpty { blocks.append(cur.joined(separator: "\n")) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return blocks.isEmpty && !trimmed.isEmpty ? [text] : blocks
    }
    static func splitAssignment(_ body: String) -> (String, String)? {
        if let m = body.firstIndex(of: "=") {
            let k = String(body[..<m].trimmingCharacters(in: .whitespaces))
            let v = unquote(String(body[body.index(after: m)...]))
            guard k.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { return nil }
            return (k, v)
        }
        if let m = body.firstIndex(of: ":") {
            let k = String(body[..<m].trimmingCharacters(in: .whitespaces))
            let v = unquote(String(body[body.index(after: m)...]))
            guard k.range(of: "^[A-Za-z_][A-Za-z0-9_.-]*$", options: .regularExpression) != nil, !v.isEmpty else { return nil }
            return (k, v)
        }
        return nil
    }
    static func assignments(text: String) -> [String: String] {
        var r: [String: String] = [:]
        for raw in lines(text) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if line.hasPrefix("export ") { line.removeFirst(7) }
            if let p = splitAssignment(line) { r[p.0] = p.1 }
        }
        return r
    }
    static func assignments(_ data: Data) -> [String: String] {
        assignments(text: decode(data)?.text ?? (String(data: data, encoding: .utf8) ?? ""))
    }
    static func sections(_ data: Data) -> [String: [String: String]] {
        guard let text = decode(data)?.text ?? String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: [String: String]] = [:], current = ""
        for raw in lines(text) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                result[current] = [:]; continue
            }
            guard !current.isEmpty, let p = splitAssignment(line) else { continue }
            result[current, default: [:]][p.0] = p.1
        }
        return result
    }
    static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func yamlListRecords(_ text: String, under listKey: String) -> [[String: String]] {
        guard text.contains("\(listKey):") else { return [] }
        var records: [[String: String]] = [], current: [String: String] = [:], inList = false
        for raw in lines(text) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed == "\(listKey):" || trimmed.hasPrefix("\(listKey):") { inList = true; continue }
            guard inList else { continue }
            if trimmed.hasPrefix("- ") {
                if !current.isEmpty { records.append(current) }
                current = [:]
                let first = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let p = splitAssignment(first) { current[p.0] = p.1 }
                continue
            }
            if let p = splitAssignment(trimmed) { current[p.0] = p.1 }
        }
        if !current.isEmpty { records.append(current) }
        return records
    }

    static func yamlMapRecords(_ text: String, under mapKey: String) -> [(String, [String: String])] {
        guard text.contains("\(mapKey):") else { return [] }
        var records: [(String, [String: String])] = []
        var currentName = ""
        var current: [String: String] = [:]
        var inMap = false
        var mapIndent = 0
        func finish() {
            if !currentName.isEmpty { records.append((currentName, current)) }
            currentName = ""; current = [:]
        }
        for raw in lines(text) {
            let indent = raw.prefix { $0 == " " }.count
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            if trimmed == "\(mapKey):" || trimmed.hasPrefix("\(mapKey):") {
                inMap = true; mapIndent = indent; continue
            }
            guard inMap else { continue }
            if indent <= mapIndent { finish(); inMap = false; continue }
            if indent == mapIndent + 2, trimmed.hasSuffix(":"), !trimmed.contains(" ") {
                finish()
                currentName = String(trimmed.dropLast())
                continue
            }
            if let pair = splitAssignment(trimmed) { current[pair.0] = pair.1 }
        }
        finish()
        return records
    }

    static func field(_ object: [String: Any], _ names: [String]) -> String? {
        for name in names {
            for (k, v) in object where k.caseInsensitiveCompare(name) == .orderedSame {
                if let s = v as? String, !s.isEmpty { return s }
            }
        }
        return nil
    }
    static func fieldDeep(_ object: Any, names: [String]) -> String? {
        if let d = object as? [String: Any] {
            if let x = field(d, names) { return x }
            for v in d.values { if let x = fieldDeep(v, names: names) { return x } }
        }
        if let a = object as? [Any] { for v in a { if let x = fieldDeep(v, names: names) { return x } } }
        return nil
    }
    static func looksBinary(_ data: Data) -> Bool { data.prefix(4096).contains(0) }
}
