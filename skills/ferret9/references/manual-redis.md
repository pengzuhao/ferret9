# redis

源文件在 `instances` 下，字段是 `host`、`user`、`password`。密码用 `REDISCLI_AUTH`，不用 `-a`，避免出现在进程参数里。来源：[redis-cli](https://redis.io/docs/latest/develop/tools/cli/) 的 `PING`、`INFO`、`DBSIZE`。该页的 `-a` 示例不要照搬。

```text
REDISCLI_AUTH=<密码> redis-cli --user <user> -h <host> -p 6379 PING
REDISCLI_AUTH=<密码> redis-cli --user <user> -h <host> -p 6379 INFO server
REDISCLI_AUTH=<密码> redis-cli --user <user> -h <host> -p 6379 DBSIZE
```

阿里云 Redis 若开了 TLS，端口仍是实例端口（常见 6379），再加 `--tls`。`--insecure` 只用于排查证书，不作为默认。

`SET`、`DEL`、`FLUSHDB` 会改数据，不用于探活。

2026-11-25 对一个 dev 实例发了 `PING`。明文失败；加 `--tls --insecure` 后报 `SSL_connect failed: unexpected eof while reading`。没有再试 prod。
