---
name: ferret9
description: Use ferret9 list to pick ops credentials and ferret9 run to execute kubectl, aliyun, aws, gh, ssh, or curl. Use when a task needs a cluster, cloud, DNS, OSS, or API credential, or access is denied.
license: MIT
compatibility: Requires the ferret9 command and its macOS service. List output has no secrets.
metadata:
  author: Ferret9
  version: "0.0.1"
---

# Ferret9 凭据目录

本地凭据库的目录。清单不在本 skill 里：导入、改说明、从列表移除之后，下一次 `ferret9 list` 就是新的。把名称抄进 skill 会过期，也会把账号清单留在每个 agent 的上下文里。

## When to Use

用户要查或改集群、云资源、DNS、OSS、发 API，或说「用凭据」「没权限」「连不上」时先读本 skill，再跑命令。

不要用于：改 Ferret9 自己的源码；用户已经给出可用的官方配置路径并明确要求直接用那个文件。

## Prerequisites

- `ferret9` 在 `PATH` 上，服务已启动。命令不存在或连不上服务时直接说明，不要改去读家目录里的 kubeconfig、云 CLI 配置或密钥文件。
- `list`、`test`、`run` 不弹授权框。`rename` 会弹出系统授权，需要人点允许。
- `kubectl`、`aliyun`、`aws`、`gh`、`ssh` 只通过 `ferret9 run` 执行。直接调用会被本机 hook 拒绝。

## Procedure

1. 列目录。每次都跑，禁止沿用上一轮记住的结果。完成标准：拿到本次命令的退出码和 stdout。

   `terminal`：`ferret9 list`

   第一行是条数说明，不是一条凭据。其后每行用制表符分开：名称、类型、说明、指纹。没有密钥。

2. 用本次 list 的「说明」列跟用户的话做语义匹配。说明是主依据：环境、产品、集群、region、只读还是可写，都只从说明里读。类型只用来排除种类不对的行，对照见 `references/task-to-credential.md`。要执行这类命令时，先读 `references/invocation.md` 的索引，再只读对应的 `references/manual-<kind>.md`。不要提前把手册读完。名称是稳定标识，不拿来猜用途。完成标准：匹配依据能引用本次 list 里某一行说明的原文，或明确说没有一行的说明对得上。

3. 按这个格式回报：
   - 匹配的名称、类型、说明
   - 匹配依据：说明里的哪几个词对上了用户的话
   - 没有匹配：不要用名称或类型硬凑。缺的是说明。请人在 App 里选中该条，把说明改成用户会说的那些词，再点「保存更改」

4. 要改说明时，等人确认后再跑 `ferret9 rename <名称> "<新说明>"`。写法见 `references/detail-writing-guide.md`。完成标准：命令退出码为 0，或已说明授权被取消。

5. 需要确认这条还能用时跑 `ferret9 test <名称>`。只转述成败，不复读输出里的密串。

6. 真正要执行时用 `ferret9 run`，不要自己拼 `KUBECONFIG`、`--profile` 或 `GH_TOKEN`。临时文件由 ferret9 建、用完即删，路径不会出现在命令里。

   `terminal`：`ferret9 run <名称> -- kubectl get ns`

   `terminal`：`ferret9 run <名称> -- aliyun ecs DescribeRegions`

   `--` 后面是官方命令和它自己的参数。写操作在 `--` 前加 `--reviewed`，表示这一步已经过用户确认：`ferret9 run --reviewed <名称> -- kubectl apply -f x.yaml`。没加时照样执行，但审计里 `reviewed` 记为 false。

   完成标准：退出码和输出都来自这一次 `ferret9 run`。输出里出现密钥就停，不要复读。

7. 每次 `run` 都在 `~/.ferret9/audit/<当天日期>.jsonl` 追加一行：时间、会话、凭据名、类型、命令、是否带 `--reviewed`、退出码、输出。查审计用 `tail` 这个文件，不要读家目录里的凭据文件。

## Pitfalls

- 不读家目录的 kubeconfig、云 CLI 配置或密钥文件来绕过 list。
- 不直接跑 `kubectl`、`aliyun`、`aws`、`gh` 或 `ssh`，也不要设置 `KUBECONFIG`、`AWS_ACCESS_KEY_ID`、`GH_TOKEN` 这类变量。hook 会拒绝直接调用。
- 不替用户导入、替换或从列表移除。
- list 失败时不编造账号。
- 说明为空，或仍是导入时识别器生成的占位（例如只有一个 context 名），就当没写。请人在 App 右侧改完再保存，不要猜。
- list 为空：先请人在 App 里导入。`run` 代发 kubeconfig、aliyun、aws、cloudflare、feishu、private-key、github。ossutil 和 redis 还没有代发，请人用官方 CLI，不要把密钥贴进对话。
- 导入步骤只告诉人，自己不做：顶栏「导入」→ 选择文件，或粘贴（文件名和放入目录必填）→ 左侧出现候选 → 双击一行并点允许。粘贴框里填的说明不会入库。

## Verification

回报里的每一条名称都能在同一次 `ferret9 list` 的输出里找到，且回复里没有密钥或指纹以外的密文。
