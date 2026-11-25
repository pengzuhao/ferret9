import Foundation

public enum OriginLookup {
    public static func locate(name: String, kind: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        guard let relatives = directories[kind] else { return nil }
        var best: (score: Int, path: String)?
        var tied = false
        for relative in relatives {
            let dir = home.appendingPathComponent(relative)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { continue }
            for file in names {
                let path = dir.appendingPathComponent(file).path
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let score = match(name, base(file))
                guard score > 0 else { continue }
                if let best, score == best.score {
                    tied = true
                } else if best == nil || score > best!.score {
                    best = (score, path)
                    tied = false
                }
            }
        }
        return tied ? nil : best?.path
    }

    static func base(_ file: String) -> String {
        var s = file
        while s.hasPrefix(".") { s.removeFirst() }
        let known = ["yaml", "yml", "json", "txt", "pem", "ini", "cfg", "conf"]
        if let dot = s.lastIndex(of: "."), dot != s.startIndex {
            let ext = String(s[s.index(after: dot)...]).lowercased()
            if known.contains(ext) { s = String(s[..<dot]) }
        }
        while s.hasPrefix(".") { s.removeFirst() }
        return s
    }

    static func match(_ name: String, _ base: String) -> Int {
        guard !name.isEmpty, !base.isEmpty else { return 0 }
        if name == base { return 1000 + base.count }
        if name.hasPrefix(base + "-") { return 500 + base.count }
        let foldedName = name.replacingOccurrences(of: "-", with: "")
        let foldedBase = base.replacingOccurrences(of: "-", with: "")
        if foldedName == foldedBase { return 400 + base.count }
        return 0
    }

    private static let directories = [
        "kubeconfig": [".kube"],
        "aliyun": [".aliyun"],
        "aws": [".aws"],
        "ossutil": ["."],
        "private-key": [".ssh"],
        "redis": [".redis"],
        "cloudflare": [".cloudflare"],
        "feishu": [".feishu"],
        "github": [".github"],
        "tcloud": [".tcloud"],
    ]
}
