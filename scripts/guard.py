#!/usr/bin/env python3
"""Block reading credential files into an agent transcript.

One script, every agent. The caller passes the agent name as the first
argument and the event JSON on stdin. Exit 0 always means "answered"; the
decision lives in the JSON on stdout, except for agents that only honour an
exit code, which get exit 2 on a block. A crash exits non-zero so the agents
configured fail-closed will block rather than let the read through.
"""
import json
import os
import re
import sys

REASON = "凭据文件不经 Ferret9 读。改跑 ferret9 list 选凭据。"

PROTECTED = (
    ".kube", ".aliyun", ".aws", ".ssh", ".cloudflare",
    ".ossutilconfig", ".netrc",
)
PROTECTED_DIRS = (".config/gh", ".config/gcloud", ".config/ferret9")
SHELL_FILES = (".zshrc", ".bashrc", ".zprofile", ".bash_profile")
READ_TOOLS = {"read", "read_file", "view"}
SHELL_TOOLS = {"bash", "terminal", "shell", "runcommand"}
OFFICIAL = {"kubectl", "aliyun", "ossutil", "aws", "ssh", "gh",
            "terraform", "helm", "redis-cli"}
DUMPERS = {"cat", "head", "tail", "less", "more", "sed", "awk",
           "bat", "nl", "strings", "base64", "xxd", "od"}
EVAL = {"python", "python3", "ruby", "perl", "node"}


def home_path(value):
    """Return the path relative to $HOME, or None when it is outside."""
    if not isinstance(value, str) or not value:
        return None
    expanded = os.path.expanduser(value)
    home = os.path.expanduser("~")
    if expanded == home:
        return ""
    prefix = home + os.sep
    if expanded.startswith(prefix):
        return expanded[len(prefix):]
    return None


def protected(path):
    rel = home_path(path)
    if rel is None:
        return False
    name = rel.split(os.sep, 1)[0]
    if name in PROTECTED or rel in SHELL_FILES:
        return True
    return any(rel == d or rel.startswith(d + os.sep) for d in PROTECTED_DIRS)


def command_blocked(command):
    if not isinstance(command, str) or not command.strip():
        return False
    head = command.strip().split()[0]
    head = os.path.basename(head)
    if head in OFFICIAL:
        return False
    mentions = protected_mentioned(command)
    if head in DUMPERS and mentions:
        return True
    if head in EVAL and re.search(r"\s-[ce]\b", command) and mentions:
        return True
    return False


def protected_mentioned(command):
    home = os.path.expanduser("~")
    for match in re.finditer(re.escape(home) + r"\S*", command):
        if protected(match.group(0).strip("'\"`):;,()")):
            return True
    for match in re.finditer(r"~\S*", command):
        if protected(match.group(0).strip("'\"`):;,()")):
            return True
    return False


def decide(payload):
    tool = str(payload.get("tool_name") or payload.get("toolName") or "").lower()
    inner = payload.get("tool_input") or payload.get("toolArgs") or {}
    if not isinstance(inner, dict):
        inner = {}
    path = (payload.get("file_path") or payload.get("filePath")
            or inner.get("file_path") or inner.get("path"))
    command = payload.get("command") or inner.get("command")
    if tool in READ_TOOLS or (path and not command):
        return protected(path)
    if tool in SHELL_TOOLS or command:
        return command_blocked(command)
    return False


def emit(agent, block):
    if agent == "cursor":
        if block:
            out = {"permission": "deny", "user_message": REASON, "agent_message": REASON}
        else:
            out = {"permission": "allow"}
    elif agent in ("claude", "qoder", "lingma", "trae", "codebuddy", "copilot"):
        if block:
            out = {"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny",
                "permissionDecisionReason": REASON}}
        else:
            out = {}
    elif agent == "hermes":
        out = {"action": "block", "message": REASON} if block else {"action": "allow"}
    elif agent in ("codex", "kimi"):
        if block:
            print(REASON, file=sys.stderr)
            return 2
        return 0
    else:
        print("未知 agent：" + agent, file=sys.stderr)
        return 1
    json.dump(out, sys.stdout, ensure_ascii=False)
    return 2 if agent == "lingma" and block else 0


def main():
    agent = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("FERRET9_AGENT", "")
    if not agent:
        print("用法：guard.py <agent>", file=sys.stderr)
        return 1
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        print("输入不是 JSON", file=sys.stderr)
        return 1
    return emit(agent, decide(payload))


if __name__ == "__main__":
    sys.exit(main())
