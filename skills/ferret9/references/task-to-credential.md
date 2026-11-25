# 任务 → 凭据类型

这张表只把任务映射到 `ferret9 list` 的类型列。账号名称以当次 `ferret9 list` 为准，不写在这里。

| 任务关键词 | kind | 说明里常见的词 | 怎么执行 |
|-----------|------|----------------|----------|
| kubectl、ACK、pod | kubeconfig | context、集群名 | `ferret9 run <名称> -- kubectl ...` |
| 阿里云、aliyun | aliyun | region、profile、只读 | `ferret9 run <名称> -- aliyun ...` |
| OSS、ossutil | ossutil | endpoint | 没有代发，请人用官方 CLI |
| Cloudflare、DNS | cloudflare | 账户、token 名称 | `ferret9 run <名称> -- curl ...` |
| 飞书 | feishu | 应用 | `ferret9 run <名称> -- curl ...` |
| AWS | aws | profile | `ferret9 run <名称> -- aws ...` |
| GitHub、API key | token | 产品名 | `ferret9 run <名称> -- gh ...` |
| SSH 私钥 | private-key | 主机或用途 | `ferret9 run <名称> -- ssh ...` |

一次任务可能要两行，例如集群加 DNS 要 kubeconfig 和 cloudflare。以当次 list 为准。

调用索引在 `invocation.md`。具体例子在 `manual-<kind>.md`，只读要用的那一类。
