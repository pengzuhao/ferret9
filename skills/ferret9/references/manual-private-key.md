# private-key

`ferret9 run` 代发。源文件是 PEM。`ssh` 会加上 `-i <临时文件>` 和 `IdentitiesOnly=yes`。`ssh-keygen -lf` 会收成 `-l -f <临时文件>`，避免 macOS 把 `-lf` 里的 `-f` 再吃掉下一个参数。私钥内容不进参数。来源：`ssh(1)` 的 `-i`，`ssh-keygen(1)` 的 `-l -f`。

```text
ferret9 run <名称> -- ssh-keygen -lf
ferret9 run <名称> -- ssh -o BatchMode=yes <user>@<host>
ferret9 run <名称> -- ssh -o BatchMode=yes <user>@<host> hostname
```

第一条只读本地指纹，不联网。后两条会连到机器。`BatchMode=yes` 避免交互问密码。

2026-11-25 只跑了 `ssh-keygen -lf`，读到 256 位指纹。没有拿私钥去连主机。
