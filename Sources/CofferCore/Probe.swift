import Foundation

public enum Probe {
    public static func run(_ item: StoredCredential) -> String {
        switch item.kind {
        case "kubeconfig": return kube(item)
        case "aliyun": return aliyun(item)
        case "aws", "ossutil": return "已保存 \(item.kind)，第一版不代发请求"
        case "cloudflare":
            let a = item.fields["account"] ?? "default"
            return "已保存 Cloudflare \(a)，第一版不代发 API"
        case "feishu": return "已保存飞书应用凭据，第一版不代发 API"
        case "redis": return "已保存 Redis \(item.fields["instance"] ?? item.name)，第一版不代发连接"
        case "private-key": return "已保存私钥，不提供探测"
        case "github": return "已保存 github"
        case "tcloud": return "已保存 tcloud"
        default: return "已保存，类型 \(item.kind)"
        }
    }

    private static func kube(_ item: StoredCredential) -> String {
        guard let doc = item.fields["document"] else { return "kubeconfig 缺失" }
        let f = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ferret9-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: f) }
        do {
            try doc.write(to: f, atomically: true, encoding: .utf8)
            var args = ["--kubeconfig", f.path, "config", "view", "--minify", "-o", "jsonpath={.contexts[0].context.cluster}"]
            if let ctx = item.fields["context"], !ctx.isEmpty { args.insert(contentsOf: ["--context", ctx], at: 2) }
            let kubectl = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/kubectl") ? "/opt/homebrew/bin/kubectl" : "/usr/local/bin/kubectl"
            let out = try run(kubectl, args)
            return out.isEmpty ? "kubeconfig 可读" : "集群：\(out)"
        } catch { return "探测失败：\(error.localizedDescription)" }
    }

    private static func aliyun(_ item: StoredCredential) -> String {
        guard let k = item.fields["access_key_id"], let s = item.fields["access_key_secret"] else { return "字段缺失" }
        let region = item.fields["region"] ?? "cn-hangzhou"
        let url = AliyunSignature.url(endpoint: "ecs.\(region).aliyuncs.com",
                                      parameters: ["Action": "DescribeRegions", "Version": "2014-05-26", "AccessKeyId": k, "RegionId": region],
                                      secret: s)
        do {
            let data = try HTTP.get(url)
            let o = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let code = o?["Code"] as? String { return "阿里云 \(code)" }
            return "阿里云只读探测成功"
        } catch { return "探测失败：\(error.localizedDescription)" }
    }

    private static func run(_ path: String, _ args: [String]) throws -> String {
        try Runner.execute(path, args, env: [:]).output
    }
}

enum HTTP {
    final class Box { var data: Data?; var err: Error? }
    static func get(_ url: URL) throws -> Data {
        let box = Box(), g = DispatchGroup()
        g.enter()
        URLSession.shared.dataTask(with: url) { d, _, e in box.data = d; box.err = e; g.leave() }.resume()
        _ = g.wait(timeout: .now() + 25)
        if let e = box.err { throw e }
        return box.data ?? Data()
    }
}
