# cloudflare

`ferret9 run` 代发。源文件字段是 `api-token`。本机没有 Cloudflare 官方 CLI，所以 `--` 后面写 `curl`。token 写进临时的 curl 配置，用 `--config` 带上，不进 URL，也不进你写的参数。

来源：[Verify Token](https://developers.cloudflare.com/api/resources/user/subresources/tokens/methods/verify/)。列 zone、列 DNS 见 [Zones](https://developers.cloudflare.com/api/resources/zones/methods/list/)。

```text
ferret9 run <名称> -- curl -sS https://api.cloudflare.com/client/v4/user/tokens/verify
ferret9 run <名称> -- curl -sS "https://api.cloudflare.com/client/v4/zones?per_page=5"
ferret9 run <名称> -- curl -sS "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records?per_page=5"
```

不要自己加 `Authorization` 头。`POST`、`PUT`、`PATCH`、`DELETE` 会改 DNS 或账号，不用于探活。

2026-11-25 用 verify 探过，`success=true`，`result.status=active`。后两条本轮没有发。
