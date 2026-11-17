# Ferret9 0.1.0

本机凭据箱。敏感材料由系统用户 `_ferret9` 持有，数据在 `/var/db/ferret9`，socket 由 launchd 创建在 `/var/run/ferret9.sock`。菜单栏 App、`ferret9` CLI、LaunchDaemon `com.ferret9.service` 共用这个 socket。识别在本机完成，不把密钥交给模型。`/usr/local/bin/coffer` 是指向 `ferret9` 的兼容链接。

## 构建与测试

```bash
bash scripts/build.sh build/bin
build/bin/ferret9-tests
```

打包产物写到 `/tmp`，不要在仓库里留下 `.app`：

```bash
bash scripts/package.sh
```

## 识别

文件、剪贴板、stdin 走同一条管线：多编码解码、按空行或 `---` 分段、结构化 detector、启发式 token。没有候选时仍返回编码、分段和已尝试的 detector。

当前类型：kubeconfig、阿里云 JSON / 环境变量、AWS INI、ossutil INI、Cloudflare YAML（`accounts` + `api-token`）、PEM 私钥、`API_KEY` / `TOKEN` 赋值、`ghp_` / `sk-` 前缀。

## CLI

```bash
ferret9 list
ferret9 inspect <文件>
ferret9 inspect - [标签]          # stdin
ferret9 paste [标签]              # stdin，同 inspect -
ferret9 add <名称> <文件>
ferret9 add-paste <名称> <标签>   # stdin
ferret9 rename <名称> <说明>
ferret9 replace <名称> <文件>
ferret9 delete <名称>
ferret9 test <名称>
```

`list`、`inspect`、`paste`、`test` 不需要授权。`add`、`rename`、`replace`、`delete` 会弹出系统授权。清单只有名称、类型、说明、指纹。

## Skill

`skills/ferret9/` 是一份 [Agent Skills](https://agentskills.io/specification) 包，目录名与 frontmatter 的 `name` 都是 `ferret9`。它不含凭据清单，agent 每次自己跑 `ferret9 list`。

仓库公开在 [github.com/pengzuhao/ferret9](https://github.com/pengzuhao/ferret9)。不要把 skill 只拷进某一台机器的 agent 目录当作发布。

Hermes 直接安装（[tap 布局](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills) 的默认扫描路径就是 `skills/`）：

```bash
hermes skills install pengzuhao/ferret9/skills/ferret9
```

订阅整个仓库再装：

```bash
hermes skills tap add pengzuhao/ferret9
hermes skills install pengzuhao/ferret9/skills/ferret9
```

Cursor、Codex、Claude Code 用 skills CLI。`skills/` 是它的优先发现目录：

```bash
npx skills add pengzuhao/ferret9 --skill ferret9
```

Hermes 安装时会带上 `SKILL.md` 引用的 `references/`。装完要新开一轮会话，已打开的会话不会重新加载 skill。
