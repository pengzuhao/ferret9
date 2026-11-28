# tcloud

`ferret9 run` 代发。`--` 后面写 `tccli` 和它自己的参数。SecretId、SecretKey 放进 `TENCENTCLOUD_SECRET_ID`、`TENCENTCLOUD_SECRET_KEY`，不进参数。来源：本机 tccli `options_define.py` 的这两个环境变量名。

凭据里没有 region。要查或改资源时，region 写在命令里。

```text
ferret9 run <名称> -- tccli tke DescribeClusters --region ap-guangzhou
```

`DescribeClusters` 只读。建节点池、删除集群这类写操作不用于探活。
