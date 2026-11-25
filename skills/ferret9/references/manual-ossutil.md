# ossutil

本机是 ossutil 2.2.0。临时文件是 INI，官方参数 `--config-file`（短写 `-c`）。来源：`ossutil config --help` 给出的文件格式，以及 `ossutil ls --help` 的列举示例。region 没有时从 `oss-<region>.aliyuncs.com` 取，endpoint 用 `--endpoint` 传。

```text
[default]
accessKeyID=...
accessKeySecret=...
region=cn-shanghai
```

`ferret9 run` 还没有代发 ossutil。

```text
ossutil ls --config-file <临时文件> --endpoint <endpoint> --limited-num 1
ossutil ls oss://<bucket> --config-file <临时文件> --limited-num 20
ossutil stat oss://<bucket> --config-file <临时文件>
```

`cp`、`rm`、`sync` 会写或删对象，不用于探活。

2026-11-25 用第一条探过，退出码 0，列出了 bucket。
