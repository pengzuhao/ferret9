---
name: ferret9
description: Use ferret9 list to pick ops credentials. Use when a task needs a cluster, cloud, DNS, OSS, or API credential, or access is denied.
license: MIT
compatibility: Requires the ferret9 command and its macOS service. List output has no secrets.
metadata:
  author: Ferret9
  version: "0.1.0"
---

# Ferret9 凭据目录

本地凭据库的目录。清单不在本 skill 里：导入、改说明、从列表移除之后，下一次 `ferret9 list` 就是新的。把名称抄进 skill 会过期，也会把账号清单留在每个 agent 的上下文里。

## When to Use

用户要查或改集群、云资源、DNS、OSS、发 API，或说「用凭据」「没权限」「连不上」时先读本 skill，再跑命令。

不要用于：改 Ferret9 自己的源码；用户已经给出可用的官方配置路径并明确要求直接用那个文件。

## Prerequisites

- `ferret9` 在 `PATH` 上，服务已启动。命令不存在或连不上服务时直接说明，不要改去读家目录里的 kubeconfig、云 CLI 配置或密钥文件。
- `list` 和 `test` 不弹授权框。`rename` 会弹出系统授权，需要人点允许。

## Procedure

1. 列目录。每次都跑，禁止沿用上一轮记住的结果。完成标准：拿到本次命令的退出码和 stdout。

   `terminal`：`ferret9 list`

   第一行是条数说明，不是一条凭据。其后每行用制表符分开：名称、类型、说明、指纹。没有密钥。

2. 用说明、类型、名称和用户话里的环境做语义匹配。类型对照见 `references/task-to-credential.md`，那只是类型映射，不是账号清单。完成标准：匹配依据能指回本次 list 的某一行，或明确说没有匹配。

3. 按这个格式回报：
   - 匹配的名称、类型、说明
   - 匹配依据（用户话里的环境、产品或集群）
   - 没有匹配：缺哪一类，请人在 App 里导入并写好说明

4. 要改说明时，等人确认后再跑 `ferret9 rename <名称> "<新说明>"`。写法见 `references/detail-writing-guide.md`。完成标准：命令退出码为 0，或已说明授权被取消。

5. 需要确认这条还能用时跑 `ferret9 test <名称>`。只转述成败，不复读输出里的密串。

## Pitfalls

- 不读家目录的 kubeconfig、云 CLI 配置或密钥文件来绕过 list。
- 不替用户导入、替换或从列表移除。
- list 失败时不编造账号。
- list 为空：先请人在 App 里导入。库里有凭据但没有代发接口时，请人用官方 CLI，不要把 token 贴进对话。

## Verification

回报里的每一条名称都能在同一次 `ferret9 list` 的输出里找到，且回复里没有密钥或指纹以外的密文。
