# github

`ferret9 run` 代发。`ghp_` 放进 `GH_TOKEN`，并设 `GH_PROMPT_DISABLED=1`。密钥不进参数。`--` 后面写 `gh` 和它自己的参数。

来源：[gh api](https://cli.github.com/manual/gh_api)。该页的只读例子是列 release、搜索 issue、用 `--jq` 取标题。`user` 是同一套 API 的当前用户。

```text
ferret9 run <名称> -- gh api user --jq .login
ferret9 run <名称> -- gh api user/orgs --jq ".[].login"
ferret9 run <名称> -- gh api repos/<owner>/<repo>/releases
ferret9 run <名称> -- gh api -X GET search/issues -f q="repo:<owner>/<repo> is:open"
```

带 `-f body=`、`-X PATCH`、`-X POST` 的例子会写数据，不用于探活。

`sk-` 开头的密钥没有对应命令，`run` 不会代发。

2026-11-25 用 `gh api user` 探过，返回了 login。
