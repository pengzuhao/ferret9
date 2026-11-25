# 拦住 agent 直接读凭据文件

不用克隆仓库。一条命令装好守卫和 skill，并当场验证：

```bash
curl -fsSL https://raw.githubusercontent.com/pengzuhao/ferret9/main/scripts/install-guard.sh | bash
```

只给某一个 agent 装，把名字加在后面：

```bash
curl -fsSL https://raw.githubusercontent.com/pengzuhao/ferret9/main/scripts/install-guard.sh | bash -s cursor
```

可选的名字：`cursor`、`claude`、`codex`、`hermes`、`copilot`、`qoder`、`lingma`、`trae`、`codebuddy`、`kimi`。

再跑一次是覆盖，不是叠加。脚本用固定标记认出自己上次写的条目，先删掉再重写。skill 写到每个装上的 agent 的 `skills/ferret9`，另写一份到 `~/.agents/skills/ferret9`。

## 它拦什么

拦两类。一类是「把密钥读进对话」，一类是「绕过 `ferret9 run`，让命令不进审计」。

拒绝这三类：

- 读文件工具打开家目录下的 `.kube`、`.aliyun`、`.aws`、`.ssh`、`.cloudflare`、`.ossutilconfig`、`.netrc`、`.config/gh`、`.config/gcloud`、`.config/ferret9`，以及 `.zshrc`、`.bashrc`、`.zprofile`、`.bash_profile`。
- shell 里点了这些路径，不管开头是 `cat`、`python -c` 还是 `export`。
- 直接跑 `kubectl`、`aliyun`、`aws`、`gh`、`ssh`。这几条必须写成 `ferret9 run <名称> -- <命令>`，这样临时文件由 ferret9 建、命令进 `~/.ferret9/audit/`。`ferret9` 和 `coffer` 开头的命令放行。

拦不住的也说清楚。模型不调用工具、直接在回复里背出密钥，hook 看不见。官方命令把密钥打到自己的标准输出，内容还是会进对话，这要靠命令本身不打印密钥。

## 验证做了什么

安装脚本对每个装上的 agent 跑 `scripts/check-guard.py`。它给守卫脚本喂五条样本，看回答对不对：

| 样本 | 应有的结果 |
|------|------------|
| 读文件工具打开 `~/.kube/config` | 拒绝 |
| 读文件工具打开 `~/notes.txt` | 放行 |
| `cat ~/.kube/config` | 拒绝 |
| `kubectl get ns` | 拒绝 |
| `aliyun ecs DescribeRegions` | 拒绝 |
| `aws sts get-caller-identity` | 拒绝 |
| `gh api user` | 拒绝 |
| `ssh user@host` | 拒绝 |
| `ferret9 run config-lab -- kubectl get ns` | 放行 |
| `python3 -c` 打开 `~/.kube/config` | 拒绝 |

这是在测守卫脚本的判断，不是在驱动 agent 本身。agent 大多只在启动时加载 hook，所以装完要重启那个 agent，拦截才生效。

## 让模型来装

把下面这段交给 agent，让它自己装、自己验证：

> 运行这一条命令：`curl -fsSL https://raw.githubusercontent.com/pengzuhao/ferret9/main/scripts/install-guard.sh | bash`。看最后一行。安装数应等于这台机器上装了的 agent 数，跳过的是没装的，验证失败必须是 0。退出码不是 0 就停下，把失败的样本贴出来，不要重试着改配置。退出码是 0 后，逐个确认写进去的配置：Cursor 的 `~/.cursor/hooks.json` 里 `beforeReadFile` 和 `beforeShellExecution` 各有一条带 `failClosed: true` 的条目；Claude Code、Qoder、通义灵码、CodeBuddy 的 `settings.json` 里 `PreToolUse` 的 matcher 是 `Read|Bash`；TRAE 的 `~/.trae-cn/hooks.json` 里 matcher 是 `Read|RunCommand`；GitHub Copilot CLI 的 `~/.copilot/hooks.json` 里事件名是 `preToolUse`；Codex 的 `~/.codex/config.toml` 里 `~/.kube` 等路径是 `deny`，另有一条 `hooks.PreToolUse` 匹配 `Bash`；Hermes 的 `~/.hermes/config.yaml` 里 `pre_tool_call` 匹配 `read_file|terminal` 且 `fail_closed: true`；Kimi Code CLI 的 `~/.kimi-code/config.toml` 里有一条 `event = "PreToolUse"`。最后提醒我重启这些 agent。

## 各家写到哪

| 产品 | 配置文件 | 拦截点 |
|------|----------|--------|
| Cursor | `~/.cursor/hooks.json` | `beforeReadFile`、`beforeShellExecution`，`failClosed: true` |
| Claude Code | `~/.claude/settings.json` | `PreToolUse`，matcher `Read\|Bash` |
| Codex | `~/.codex/config.toml` | `permissions.filesystem` 直接 `deny`，外加 `hooks.PreToolUse` 匹配 `Bash` |
| Hermes | `~/.hermes/config.yaml` | `pre_tool_call` 匹配 `read_file\|terminal`，`fail_closed: true` |
| GitHub Copilot CLI | `~/.copilot/hooks.json` | `preToolUse` |
| Qoder CLI | `~/.qoder/settings.json` | `PreToolUse`，matcher `Read\|Bash` |
| 通义灵码 IDE | `~/.lingma/settings.json` | 同上，改完要重启 IDE |
| TRAE | `~/.trae-cn/hooks.json` | `PreToolUse`，matcher `Read\|RunCommand` |
| CodeBuddy | `~/.codebuddy/settings.json` | `PreToolUse`，matcher `Read\|Bash`，改完要在 `/hooks` 面板审核 |
| Kimi Code CLI | `~/.kimi-code/config.toml` | `[[hooks]]`，`event = "PreToolUse"` |

文心快码没有查到官方 hook 文档，这条命令不处理它。Windsurf、Cline、Continue、Aider 的拦截格式没有逐一核对，同样不处理。

Codex 读文件靠 `permissions.filesystem` 拒绝，不靠 hook。Kimi Code CLI 官方写明脚本出错就放行，所以它这份是提醒，不是最后一道闸。
