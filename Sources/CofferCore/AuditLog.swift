import Foundation

/// One JSON object per line, one file per day, under ~/.ferret9/audit.
/// The file is 0600. Callers must already have stripped secrets.
public enum AuditLog {
    public struct Entry: Codable, Equatable {
        public var time, session, name, kind, command: String
        public var reviewed: Bool
        public var status: Int32
        public var output: String
    }

    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ferret9", isDirectory: true)
            .appendingPathComponent("audit", isDirectory: true)
    }

    public static func redact(_ text: String) -> String {
        var s = text
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if home.count > 1 { s = s.replacingOccurrences(of: home, with: "~") }
        let patterns = [
            "LTAI[A-Za-z0-9]{8,}",
            "AKIA[A-Z0-9]{16}",
            "ghp_[A-Za-z0-9]{16,}",
            "sk-[A-Za-z0-9]{16,}",
            "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(s.startIndex..., in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "[已脱敏]")
        }
        if s.count > 2000 { s = String(s.prefix(2000)) + "…(已截断)" }
        return s
    }

    public static func record(_ entry: Entry, root: URL = directory) {
        var entry = entry
        entry.command = redact(entry.command)
        entry.output = redact(entry.output)
        let day = dayStamp()
        let file = root.appendingPathComponent(day).appendingPathExtension("jsonl")
        guard let line = try? JSONEncoder().encode(entry) else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path) {
                FileManager.default.createFile(atPath: file.path, contents: nil)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line + Data("\n".utf8))
        } catch {
            fputs("审计写入失败：\(error.localizedDescription)\n", stderr)
        }
    }

    static func dayStamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
