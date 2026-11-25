# 调用方式索引

凭据只进临时文件、环境变量或请求头。临时文件权限 0600，用完就删。密钥不进命令参数。

要执行哪一类，只读对应的那一份。不要把这些文件一次读完。

| kind | 文件 | 官方命令 | 凭据放哪 | ferret9 run |
|---|---|---|---|---|
| kubeconfig | manual-kubeconfig.md | kubectl | `--kubeconfig` | 已代发 |
| aliyun | manual-aliyun.md | aliyun | `--config-path` | 已代发 |
| aws | manual-aws.md | aws | `AWS_SHARED_CREDENTIALS_FILE` | 已代发 |
| ossutil | manual-ossutil.md | ossutil | `--config-file` | 没有 |
| cloudflare | manual-cloudflare.md | curl | `--config` 里的请求头 | 已代发 |
| feishu | manual-feishu.md | curl | 先换票，再放进 `--config` | 已代发 |
| redis | manual-redis.md | redis-cli | `REDISCLI_AUTH` | 没有 |
| private-key | manual-private-key.md | ssh | `-i` | 已代发 |
| token | manual-token.md | gh | `GH_TOKEN` | 已代发 |
