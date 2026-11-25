# feishu

`ferret9 run` 代发。源文件字段是 `app_id`、`app_secret`。`--` 后面只写要调用的 `curl`。换票由 ferret9 在内部完成：用临时文件把 `app_secret` 交给 curl，不放进参数。拿到的 `tenant_access_token` 写进另一份 curl 配置，再用 `--config` 带上。票不进 URL，也不进你写的命令。

来源：[自建应用获取 tenant_access_token](https://open.feishu.cn/document/server-docs/authentication-management/access-token/tenant_access_token_internal)。该页写明这是历史版本。请求体仍是 `app_id` 和 `app_secret`。成功时 `code` 为 0。票最长 2 小时。

```text
ferret9 run <名称> -- curl -sS https://open.feishu.cn/open-apis/bot/v3/info
```

不要自己先换票，也不要自己加 `Authorization` 头。

2026-11-25 探过换票和 bot info，两处 `code` 都是 0。
