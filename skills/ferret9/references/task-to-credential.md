# 任务 → 凭据类型

这张表只把任务映射到 `ferret9 list` 的类型列。账号名称以当次 `ferret9 list` 为准，不写在这里。

| 任务关键词 | kind | 说明里常见的词 |
|-----------|------|----------------|
| kubectl、ACK、pod | kubeconfig | context、集群名 |
| 阿里云、aliyun | aliyun | region、profile、只读 |
| OSS、ossutil | ossutil | endpoint |
| Cloudflare、DNS | cloudflare | 账户、token 名称 |
| AWS | aws | profile |
| GitHub、API key | token | 产品名 |
| SSH 私钥 | private-key | 主机或用途 |

一次任务可能要两行，例如集群加 DNS 要 kubeconfig 和 cloudflare。以当次 list 为准。
