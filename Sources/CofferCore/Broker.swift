import Foundation

public struct Broker {
    public var store: Store
    public var authorize: (String?) -> Bool
    public init(store: Store, authorize: @escaping (String?) -> Bool = { _ in false }) {
        self.store = store; self.authorize = authorize
    }

    public func handle(_ request: Request) -> Response {
        do {
            switch request {
            case .list:
                let items = try store.list()
                let msg = items.isEmpty ? "没有已纳管凭据" : "已纳管 \(items.count) 条"
                return Response(ok: true, message: msg, credentials: items)
            case .inspect(let path):
                return try inspectData(try Data(contentsOf: URL(fileURLWithPath: path)), source: path)
            case .inspectText(let label, let b64):
                guard let data = Data(base64Encoded: b64) else { throw CofferError.invalid("Base64 无效") }
                return try inspectData(data, source: label)
            case .add(let name, let source, let auth):
                try require(auth)
                try store.add(try Importer.select(try Data(contentsOf: URL(fileURLWithPath: source)), source: source, name: name))
                return Response(ok: true, message: "已添加 \(name)", credentials: try store.list())
            case .addInline(let name, let label, let b64, let auth):
                try require(auth)
                guard let data = Data(base64Encoded: b64) else { throw CofferError.invalid("Base64 无效") }
                try store.add(try Importer.select(data, source: label, name: name))
                return Response(ok: true, message: "已添加 \(name)", credentials: try store.list())
            case .update(let name, let detail, let source, let auth):
                try require(auth)
                let rep = try source.map { try Importer.select(try Data(contentsOf: URL(fileURLWithPath: $0)), source: $0, name: name) }
                try store.update(name: name, detail: detail, item: rep)
                return Response(ok: true, message: "已更新 \(name)", credentials: try store.list())
            case .updateInline(let name, let label, let b64, let auth):
                try require(auth)
                guard let data = Data(base64Encoded: b64) else { throw CofferError.invalid("Base64 无效") }
                let item = try Importer.select(data, source: label, name: name)
                try store.update(name: name, detail: nil, item: item)
                return Response(ok: true, message: "已更新 \(name)", credentials: try store.list())
            case .delete(let name, let auth):
                try require(auth); try store.delete(name: name)
                return Response(ok: true, message: "已删除 \(name)", credentials: try store.list())
            case .test(let name):
                let result = Probe.run(try store.record(name: name))
                if Fingerprint.containsSecret(result, secrets: try store.secrets()) {
                    return Response(ok: false, message: "输出已拦截")
                }
                return Response(ok: true, message: result)
            }
        } catch let e as CofferError { return Response(ok: false, message: e.errorDescription ?? "错误") }
        catch { return Response(ok: false, message: error.localizedDescription) }
    }

    private func inspectData(_ data: Data, source: String) throws -> Response {
        let (candidates, diag) = Importer.analyze(data: data, source: source)
        let report = InspectReport(encoding: diag.encoding, segmentCount: diag.segmentCount, attempts: diag.attempts, warnings: diag.warnings)
        if candidates.isEmpty {
            let hints = diag.attempts.isEmpty ? "" : " 已尝试：\(diag.attempts.joined(separator: "、"))。"
            return Response(ok: true, message: "没有识别出凭据。\(hints)", candidates: [], inspect: report)
        }
        let low = candidates.filter { $0.confidence == .low }.count
        var msg = "识别到 \(candidates.count) 条"
        if low > 0 { msg += "（\(low) 条低置信）" }
        return Response(ok: true, message: msg, candidates: candidates, inspect: report)
    }

    private func require(_ auth: String?) throws {
        guard authorize(auth) else { throw CofferError.refused("需要管理员授权") }
    }
}
