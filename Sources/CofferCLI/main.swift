import Foundation
import Security

var args = Array(CommandLine.arguments.dropFirst())
let socket = take("--socket", &args) ?? CofferPaths.socket

if args.first == "add-batch" {
    let auth = try ticket()
    let raw = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
    var ok = 0
    var failed = 0
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
        let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { fputs("格式错误\n", stderr); failed += 1; continue }
        let req = Request.addInline(name: parts[0], label: parts[1], contentBase64: parts[2], origin: nil, overrideName: nil, overrideKind: nil, overrideDetail: nil, authorization: auth)
        do {
            let res = try Client.call(req, socketPath: socket)
            if res.ok { ok += 1; print("OK\t\(parts[0])") }
            else { failed += 1; fputs("FAIL\t\(parts[0])\t\(res.message)\n", stderr) }
        } catch {
            failed += 1
            fputs("FAIL\t\(parts[0])\t\(error.localizedDescription)\n", stderr)
        }
    }
    print("added \(ok) failed \(failed)")
    exit(failed == 0 ? 0 : 1)
}

do {
    let req = try parse(args)
    let res = try Client.call(req, socketPath: socket)
    print(res.message)
    if let r = res.inspect {
        print("编码\t\(r.encoding)"); print("分段\t\(r.segmentCount)")
        if !r.attempts.isEmpty { print("检测\t\(r.attempts.joined(separator: ", "))") }
    }
    for c in res.credentials { print("\(c.name)\t\(c.kind)\t\(c.detail)\t\(c.fingerprint)") }
    for c in res.candidates { print("\(c.name)\t\(c.kind)\t\(c.detail)\t\(c.fingerprint)\t\(c.confidence.rawValue)") }
    exit(res.ok ? 0 : 1)
} catch {
    fputs(((error as? CofferError).map { $0.errorDescription ?? "" } ?? error.localizedDescription) + "\n", stderr)
    exit(2)
}

func parse(_ a: [String]) throws -> Request {
    switch a.first {
    case "list": return .list
    case "inspect":
        guard a.count >= 2 else { throw CofferError.invalid("inspect <文件|->") }
        if a[1] == "-" {
            let label = a.count > 2 ? a[2] : "stdin"
            return .inspectText(label: label, contentBase64: try readStdin().base64EncodedString())
        }
        return .inspect(path: a[1])
    case "paste":
        return .inspectText(label: a.count > 1 ? a[1] : "clipboard", contentBase64: try readStdin().base64EncodedString())
    case "test": guard a.count == 2 else { throw CofferError.invalid("test <名称>") }; return .test(name: a[1])
    case "add": guard a.count == 3 else { throw CofferError.invalid("add <名称> <文件>") }
        return .add(name: a[1], source: a[2], origin: nil, authorization: try ticket())
    case "add-paste": guard a.count == 3 else { throw CofferError.invalid("add-paste <名称> <标签>") }
        return .addInline(name: a[1], label: a[2], contentBase64: try readStdin().base64EncodedString(), origin: nil, overrideName: nil, overrideKind: nil, overrideDetail: nil, authorization: try ticket())
    case "rename": guard a.count == 3 else { throw CofferError.invalid("rename <名称> <说明>") }
        return .update(name: a[1], detail: a[2], kind: nil, rename: nil, source: nil, authorization: try ticket())
    case "replace": guard a.count == 3 else { throw CofferError.invalid("replace <名称> <文件>") }
        return .update(name: a[1], detail: nil, kind: nil, rename: nil, source: a[2], authorization: try ticket())
    case "replace-paste": guard a.count == 3 else { throw CofferError.invalid("replace-paste <名称> <标签>") }
        return .updateInline(name: a[1], label: a[2], contentBase64: try readStdin().base64EncodedString(), authorization: try ticket())
    case "delete": guard a.count == 2 else { throw CofferError.invalid("delete <名称>") }
        return .delete(name: a[1], authorization: try ticket())
    default: throw CofferError.invalid("list|inspect|paste|test|add|add-paste|add-batch|rename|replace|replace-paste|delete")
    }
}
func readStdin() throws -> Data {
    let d = FileHandle.standardInput.readDataToEndOfFile()
    guard !d.isEmpty else { throw CofferError.invalid("stdin 空") }
    return d
}
func take(_ n: String, _ a: inout [String]) -> String? {
    guard let i = a.firstIndex(of: n), i + 1 < a.count else { return nil }
    let v = a[i+1]; a.removeSubrange(i...i+1); return v
}
func ticket() throws -> String { try Grant.issue() }
