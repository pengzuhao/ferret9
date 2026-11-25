# aws

`ferret9 run` 代发。临时文件是共享凭据格式，段名用这条的 profile。位置放进 `AWS_SHARED_CREDENTIALS_FILE`，并用 `AWS_PROFILE` 选段。AccessKey 不出现在你写的命令里，也不出现在参数里。来源：aws-cli《The Shared Credentials File》，以及 `sts get-caller-identity` 示例。

```text
ferret9 run <名称> -- aws sts get-caller-identity
ferret9 run <名称> -- aws s3 ls
ferret9 run <名称> -- aws ec2 describe-instances --max-items 5
```

`s3 ls` 和 `ec2 describe-instances` 是 AWS CLI 用户指南里的常用只读命令。`s3 rm`、`ec2 terminate-instances` 不用于探活。

2026-11-25 用 `sts get-caller-identity` 探过，账号是 12 位数字。
