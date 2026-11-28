import Foundation

/// Runs an official CLI with a stored credential without putting the material
/// on the command line. The CLI process creates the temp file, runs the
/// command, and deletes the file. The service user cannot read the login
/// user's home, so this cannot live in the service.
public enum Runner {
    public struct Outcome: Equatable {
        public var status: Int32
        public var output: String
        public var blocked: Bool
    }

    public static let reviewFlag = "--reviewed"

    public static func run(item: StoredCredential, command: [String], reviewed: Bool, secrets: [String]) -> Outcome {
        guard !command.isEmpty else {
            return Outcome(status: 2, output: "命令为空", blocked: false)
        }
        guard let bin = command.first, !bin.contains("/") else {
            return Outcome(status: 2, output: "只接受命令名，不接受路径", blocked: false)
        }
        guard var prepared = prepare(item, command: command) else {
            return Outcome(status: 2, output: "类型 \(item.kind) 没有代发", blocked: false)
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ferret9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            if let mint = prepared.mint {
                let minted = try mint()
                prepared.body = minted.body
                prepared.extraSecrets += minted.secrets
            }
            try prepared.body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            let ran = try execute(prepared.binary, prepared.arguments(url.path), env: prepared.env(url.path))
            let text = ran.output
            if Fingerprint.containsSecret(text, secrets: secrets + prepared.extraSecrets) {
                return Outcome(status: ran.status, output: "输出已拦截", blocked: true)
            }
            return Outcome(status: ran.status, output: text, blocked: false)
        } catch {
            return Outcome(status: 2, output: "代发失败：\(error.localizedDescription)", blocked: false)
        }
    }

    struct Prepared {
        var binary: String
        var arguments: (String) -> [String]
        var env: (String) -> [String: String]
        var body: String
        var extraSecrets: [String]
        var mint: (() throws -> (body: String, secrets: [String]))?
    }

    static func prepare(_ item: StoredCredential, command: [String]) -> Prepared? {
        switch item.kind {
        case "kubeconfig":
            guard command[0] == "kubectl", let doc = item.fields["document"] else { return nil }
            return Prepared(
                binary: binary("kubectl"),
                arguments: { path in ["--kubeconfig", path] + Array(command.dropFirst()) },
                env: { _ in [:] },
                body: doc,
                extraSecrets: [],
                mint: nil)
        case "aliyun":
            guard command[0] == "aliyun",
                  let id = item.fields["access_key_id"], let secret = item.fields["access_key_secret"] else { return nil }
            let region = item.fields["region"].flatMap { $0.isEmpty ? nil : $0 } ?? "cn-hangzhou"
            let profile = item.fields["profile"].flatMap { $0.isEmpty ? nil : $0 } ?? "default"
            let body = """
            {"current":"\(profile)","profiles":[{"name":"\(profile)","mode":"AK","access_key_id":"\(id)","access_key_secret":"\(secret)","region_id":"\(region)","output_format":"json","language":"zh"}]}
            """
            return Prepared(
                binary: binary("aliyun"),
                arguments: { path in ["--config-path", path] + Array(command.dropFirst()) },
                env: { _ in [:] },
                body: body,
                extraSecrets: [id, secret],
                mint: nil)
        case "aws":
            guard command[0] == "aws",
                  let id = item.fields["access_key_id"], let secret = item.fields["access_key_secret"] else { return nil }
            let profile = item.fields["profile"].flatMap { $0.isEmpty ? nil : $0 } ?? "default"
            return Prepared(
                binary: binary("aws"),
                arguments: { _ in Array(command.dropFirst()) },
                env: { path in ["AWS_SHARED_CREDENTIALS_FILE": path, "AWS_PROFILE": profile] },
                body: "[\(profile)]\naws_access_key_id=\(id)\naws_secret_access_key=\(secret)\n",
                extraSecrets: [id, secret],
                mint: nil)
        case "cloudflare":
            guard command[0] == "curl", let token = item.fields["api_token"], !token.isEmpty else { return nil }
            return Prepared(
                binary: binary("curl"),
                arguments: { path in ["--config", path] + Array(command.dropFirst()) },
                env: { _ in [:] },
                body: "header = \"Authorization: Bearer \(token)\"\n",
                extraSecrets: [token],
                mint: nil)
        case "feishu":
            guard command[0] == "curl",
                  let app = item.fields["app_id"], let secret = item.fields["app_secret"],
                  !app.isEmpty, !secret.isEmpty else { return nil }
            return Prepared(
                binary: binary("curl"),
                arguments: { path in ["--config", path] + Array(command.dropFirst()) },
                env: { _ in [:] },
                body: "",
                extraSecrets: [secret],
                mint: {
                    let ticket = try feishuTicket(app: app, secret: secret)
                    return (body: "header = \"Authorization: Bearer \(ticket)\"\n", secrets: [ticket])
                })
        case "private-key":
            guard let doc = item.fields["document"], !doc.isEmpty else { return nil }
            switch command[0] {
            case "ssh":
                return Prepared(
                    binary: binary("ssh"),
                    arguments: { path in ["-i", path, "-o", "IdentitiesOnly=yes"] + Array(command.dropFirst()) },
                    env: { _ in [:] },
                    body: doc,
                    extraSecrets: [],
                    mint: nil)
            case "ssh-keygen":
                var rest = Array(command.dropFirst())
                if let i = rest.firstIndex(where: { $0 == "-lf" || $0 == "-fl" }) { rest[i] = "-l" }
                return Prepared(
                    binary: binary("ssh-keygen"),
                    arguments: { path in rest + ["-f", path] },
                    env: { _ in [:] },
                    body: doc,
                    extraSecrets: [],
                    mint: nil)
            default:
                return nil
            }
        case "github":
            guard command[0] == "gh", let token = item.fields["token"], !token.isEmpty,
                  !token.hasPrefix("sk-") else { return nil }
            return Prepared(
                binary: binary("gh"),
                arguments: { _ in Array(command.dropFirst()) },
                env: { _ in ["GH_TOKEN": token, "GH_PROMPT_DISABLED": "1"] },
                body: "",
                extraSecrets: [token],
                mint: nil)
        case "tcloud":
            guard command[0] == "tccli",
                  let id = item.fields["secret_id"], let key = item.fields["secret_key"],
                  !id.isEmpty, !key.isEmpty else { return nil }
            return Prepared(
                binary: binary("tccli"),
                arguments: { _ in Array(command.dropFirst()) },
                env: { _ in ["TENCENTCLOUD_SECRET_ID": id, "TENCENTCLOUD_SECRET_KEY": key] },
                body: "",
                extraSecrets: [id, key],
                mint: nil)
        default:
            return nil
        }
    }

    static func feishuTicket(app: String, secret: String) throws -> String {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ferret9-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try "{\"app_id\":\"\(app)\",\"app_secret\":\"\(secret)\"}".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let ran = try execute(binary("curl"), [
            "-sS", "--max-time", "20", "-X", "POST", "-H", "Content-Type: application/json",
            "--data-binary", "@\(url.path)",
            "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal",
        ], env: [:])
        guard let data = ran.output.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["code"] as? NSNumber)?.intValue == 0,
              let ticket = obj["tenant_access_token"] as? String, !ticket.isEmpty else {
            throw CofferError.unavailable("飞书换票失败")
        }
        return ticket
    }

    static func binary(_ name: String) -> String {
        let local = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", local] {
            let path = dir + "/" + name
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return "/usr/bin/" + name
    }

    struct Ran { var status: Int32; var output: String }

    static func execute(_ path: String, _ args: [String], env: [String: String]) throws -> Ran {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var merged = ProcessInfo.processInfo.environment
        for key in ["KUBECONFIG", "ALIBABA_CLOUD_ACCESS_KEY_ID", "ALIBABA_CLOUD_ACCESS_KEY_SECRET",
                     "ALIBABA_CLOUD_SECURITY_TOKEN", "ALIBABACLOUD_ACCESS_KEY_ID", "ALIBABACLOUD_ACCESS_KEY_SECRET",
                     "ALICLOUD_ACCESS_KEY_ID", "ALICLOUD_ACCESS_KEY_SECRET", "AWS_ACCESS_KEY_ID",
                     "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN", "AWS_PROFILE", "AWS_SHARED_CREDENTIALS_FILE",
                     "GH_TOKEN", "GITHUB_TOKEN", "TENCENTCLOUD_SECRET_ID",
                     "TENCENTCLOUD_SECRET_KEY", "TENCENTCLOUD_TOKEN"] {
            merged.removeValue(forKey: key)
        }
        env.forEach { merged[$0.key] = $0.value }
        p.environment = merged
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run(); p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let errors = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Ran(status: p.terminationStatus, output: (text + errors).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
