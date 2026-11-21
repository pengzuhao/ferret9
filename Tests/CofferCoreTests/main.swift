import Foundation

func check(_ condition: Bool, _ message: String) {
    if condition { return }
    fputs("FAIL \(message)\n", stderr)
    exit(1)
}

func kinds(_ text: String, source: String = "sample") -> [String] {
    Importer.analyze(data: Data(text.utf8), source: source).0.map(\.kind).sorted()
}

let cloudflare = """
accounts:
  - name: lab
    api-token-name: deploy
    api-token: placeholder-token-0001
"""
let cf = Importer.analyze(data: Data(cloudflare.utf8), source: "config.yaml").0
check(cf.count == 1 && cf[0].kind == "cloudflare" && cf[0].name == "config-lab", "cloudflare yaml")

let kube = """
apiVersion: v1
kind: Config
clusters:
- name: demo
contexts:
- name: demo
"""
check(kinds(kube, source: "config").contains("kubeconfig"), "kubeconfig")

let env = "ALIBABA_CLOUD_ACCESS_KEY_ID=LTAIheuristic0001\nALIBABA_CLOUD_ACCESS_KEY_SECRET=placeholder-secret-0001\n"
check(kinds(env, source: ".env").contains("aliyun"), "aliyun env")

let aliyunList = """
[{"current":"a","profiles":[{"name":"a","access_key_id":"[REDACTED:aliyun-key-id]","access_key_secret":"placeholder-secret-0001"}]},{"current":"b","profiles":[{"name":"b","access_key_id":"[REDACTED:aliyun-key-id]","access_key_secret":"placeholder-secret-0002"}]}]
"""
let aliyunItems = Importer.analyze(data: Data(aliyunList.utf8), source: "config.json-dns").0
check(aliyunItems.count == 2 && Set(aliyunItems.map(\.kind)) == ["aliyun"], "aliyun config array splits into two")
check(Set(aliyunItems.map(\.name)) == ["config.json-dns-1-a", "config.json-dns-2-b"], "aliyun array names stay distinct")

let aws = """
[default]
aws_access_key_id = AKIAIOSFODNN7EXAMPLE
aws_secret_access_key = placeholderSecretKey0001
"""
check(kinds(aws, source: "credentials").contains("aws"), "aws ini")

let pem = "-----BEGIN PRIVATE KEY-----\nplaceholder\n-----END PRIVATE KEY-----\n"
check(kinds(pem, source: "id").contains("private-key"), "pem")

let oss = """
[default]
accessKeyId=LTAIheuristic0001
accessKeySecret=placeholder-secret-0001
region=ap-southeast-1
"""
check(kinds(oss, source: "ossutilconfig").contains("ossutil"), "ossutil")

let feishu = "{\"app_id\":\"cli_placeholder\",\"app_secret\":\"placeholder-secret-0001\"}"
check(kinds(feishu, source: "config.json").contains("feishu"), "feishu")

let redis = """
instances:
  sp-dev:
    host: example.redis.aliyuncs.com
    password: placeholder-secret-0001
"""
check(kinds(redis, source: "config.yaml").contains("redis"), "redis")

let token = "github token ghp_placeholderTokenValue0001 sits in notes\n"
let tokens = Importer.analyze(data: Data(token.utf8), source: "notes.txt").0
check(tokens.contains { $0.kind == "token" && $0.confidence == .medium }, "heuristic token")

let mixed = cloudflare + "\n---\n" + kube
let mixedItems = Importer.analyze(data: Data(mixed.utf8), source: "bundle.txt").0
check(Set(mixedItems.map(\.kind)).isSuperset(of: ["cloudflare", "kubeconfig"]), "segments")

let empty = Importer.analyze(data: Data("hello world\n".utf8), source: "note.txt")
check(empty.0.isEmpty && empty.1.encoding == "utf-8" && !empty.1.attempts.isEmpty, "empty still reports")

dir: do {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("coffer-test-\(UUID().uuidString)", isDirectory: true)
    let store = Store(directory: root)
    let broker = Broker(store: store) { _ in true }
    let b64 = Data(cloudflare.utf8).base64EncodedString()
    let added = broker.handle(.addInline(name: "config-lab", label: "config.yaml", contentBase64: b64 , origin: nil, overrideName: nil, overrideKind: nil, overrideDetail: nil, authorization: "ok"))
    check(added.ok && added.credentials.count == 1, "add inline")
    let renamed = broker.handle(.update(name: "config-lab", detail: "Cloudflare lab deploy token", kind: nil, rename: nil, source: nil, authorization: "ok"))
    check(renamed.ok && renamed.credentials.first?.detail == "Cloudflare lab deploy token", "rename detail")
    let listed = broker.handle(.list)
    check(listed.credentials.first?.detail == "Cloudflare lab deploy token", "list keeps detail")
    let tested = broker.handle(.test(name: "config-lab"))
    check(tested.ok && tested.message.contains("Cloudflare"), "probe")
    let renamedId = broker.handle(.update(name: "config-lab", detail: nil, kind: "阿里云", rename: "实验室", source: nil, authorization: "ok"))
    check(renamedId.ok && renamedId.credentials.contains { $0.name == "实验室" && $0.kind == "阿里云" }, "unicode name and kind")
    let rejected = broker.handle(.update(name: "实验室", detail: nil, kind: "a/b", rename: nil, source: nil, authorization: "ok"))
    check(!rejected.ok && rejected.credentials.isEmpty, "bad kind returns no list")
    let still = broker.handle(.list)
    check(still.credentials.contains { $0.name == "实验室" && $0.kind == "阿里云" }, "rejected update does not drop record")
    try FileManager.default.removeItem(at: root)
}

origins: do {
    let home = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ferret9-home-\(UUID().uuidString)", isDirectory: true)
    func touch(_ relative: String) {
        let url = home.appendingPathComponent(relative)
        try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("x".utf8).write(to: url)
    }
    touch(".kube/config-lab")
    touch(".redis/config.yaml")
    touch(".aliyun/config.json-sample-lab")
    touch(".ossutilconfig-lab")
    touch(".ssh/id_example")
    check(OriginLookup.locate(name: "config-lab", kind: "kubeconfig", home: home)?.hasSuffix(".kube/config-lab") == true, "kube path")
    check(OriginLookup.locate(name: "config-lab-extra", kind: "redis", home: home)?.hasSuffix(".redis/config.yaml") == true, "redis path")
    check(OriginLookup.locate(name: "config.json-samplelab", kind: "aliyun", home: home)?.hasSuffix("config.json-sample-lab") == true, "aliyun folded name")
    check(OriginLookup.locate(name: "ossutilconfig-lab-default", kind: "ossutil", home: home)?.hasSuffix(".ossutilconfig-lab") == true, "ossutil path")
    check(OriginLookup.locate(name: "id_example", kind: "private-key", home: home)?.hasSuffix(".ssh/id_example") == true, "key path")
    check(OriginLookup.locate(name: "missing", kind: "kubeconfig", home: home) == nil, "unknown stays empty")
    try FileManager.default.removeItem(at: home)
}

print("ok")
