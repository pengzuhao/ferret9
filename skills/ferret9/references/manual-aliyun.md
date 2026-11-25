# aliyun

凭据放进一份临时 `config.json`，只含选中的那个 profile，`mode` 为 `AK`。官方参数是 `--config-path`（aliyun-cli 源码里的 `ConfigurePathFlagName`）。没有改配置路径的环境变量。密钥不进参数。

```text
{
  "current": "default",
  "profiles": [{
    "name": "default",
    "mode": "AK",
    "access_key_id": "...",
    "access_key_secret": "...",
    "region_id": "cn-hangzhou"
  }]
}
```

`ferret9 run` 已代发。命令形是 `aliyun <产品> <Action>`。来源：[Generate CLI commands](https://www.alibabacloud.com/help/en/cli/sample-commands)，该页用 `DescribeInstances` 做创建后的核对。

```text
ferret9 run <名称> -- aliyun ecs DescribeRegions --region cn-hangzhou
ferret9 run <名称> -- aliyun ecs DescribeInstances --RegionId cn-hangzhou
```

同一页的 `ecs CreateInstance` 会创建实例，不要当作探活用例。写操作加 `--reviewed`。

2026-11-25 用 `ecs DescribeRegions` 探过，返回里有 RegionId。
