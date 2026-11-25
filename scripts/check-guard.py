#!/usr/bin/env python3
"""Feed the guard sample events and check its answers.

Usage: check-guard.py <agent> <path-to-installed-guard>
Exits 0 when every sample got the expected decision, 1 otherwise.
"""
import json
import os
import subprocess
import sys

home = os.path.expanduser("~")
SECRET = os.path.join(home, ".kube", "config")
PLAIN = os.path.join(home, "notes.txt")

CASES = [
    ("读密钥文件应拒绝", {"tool_name": "Read", "tool_input": {"file_path": SECRET}}, True),
    ("读普通文件应放行", {"tool_name": "Read", "tool_input": {"file_path": PLAIN}}, False),
    ("cat 密钥文件应拒绝", {"tool_name": "Bash", "tool_input": {"command": "cat " + SECRET}}, True),
    ("直接 kubectl 应拒绝", {"tool_name": "Bash", "tool_input": {"command": "kubectl get ns"}}, True),
    ("直接 aliyun 应拒绝", {"tool_name": "Bash", "tool_input": {"command": "aliyun ecs DescribeRegions"}}, True),
    ("直接 aws 应拒绝", {"tool_name": "Bash", "tool_input": {"command": "aws sts get-caller-identity"}}, True),
    ("直接 gh 应拒绝", {"tool_name": "Bash", "tool_input": {"command": "gh api user"}}, True),
    ("直接 ssh 应拒绝", {"tool_name": "Bash", "tool_input": {"command": "ssh user@host"}}, True),
    ("ferret9 run 应放行",
     {"tool_name": "Bash", "tool_input": {"command": "ferret9 run config-lab -- kubectl get ns"}}, False),
    ("python 打开密钥应拒绝",
     {"tool_name": "Bash", "tool_input": {"command": "python3 -c 'open(\"%s\")'" % SECRET}}, True),
]


def blocked(agent, proc):
    if agent in ("codex", "kimi"):
        return proc.returncode == 2
    if agent == "lingma":
        return proc.returncode == 2
    if proc.returncode != 0:
        return None
    try:
        out = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return None
    if agent == "cursor":
        return out.get("permission") == "deny"
    if agent == "hermes":
        return out.get("action") == "block"
    return out.get("hookSpecificOutput", {}).get("permissionDecision") == "deny"


def main():
    agent, script = sys.argv[1], sys.argv[2]
    bad = 0
    for title, payload, expect in CASES:
        if agent == "trae" and payload["tool_name"] == "Bash":
            payload = {"tool_name": "RunCommand", "tool_input": payload["tool_input"]}
        if agent == "hermes" and payload["tool_name"] == "Bash":
            payload = {"tool_name": "terminal", "tool_input": payload["tool_input"]}
        if agent == "hermes" and payload["tool_name"] == "Read":
            payload = {"tool_name": "read_file", "tool_input": {"path": payload["tool_input"]["file_path"]}}
        proc = subprocess.run(["python3", script, agent], input=json.dumps(payload),
                              capture_output=True, text=True)
        got = blocked(agent, proc)
        if got is None or got != expect:
            bad += 1
            print("失败 %s：期望%s，得到 %s，退出码 %d" % (
                title, "拒绝" if expect else "放行", got, proc.returncode))
            if proc.stderr.strip():
                print("  stderr: " + proc.stderr.strip())
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
