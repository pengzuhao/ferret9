#!/bin/bash
# One command installs the credential-read guard into every agent it recognises
# and checks each one. Passing the agent name limits the run to that agent.
# The check feeds the guard script sample input and reads its answer. It does
# not drive the agent itself, so an agent that only loads hooks at startup
# still needs a restart before the guard applies.
set -euo pipefail

PY="python3"
command -v "$PY" >/dev/null 2>&1 || { echo "需要 python3" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "需要 curl" >&2; exit 1; }

REPO="https://raw.githubusercontent.com/pengzuhao/ferret9/main"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORKDIR="$(mktemp -d /tmp/ferret9-guard.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

fetch() {
  local name="$1"
  if [[ -f "$HERE/$name" ]]; then
    cp "$HERE/$name" "$WORKDIR/$name"
  else
    curl -fsSL "$REPO/scripts/$name" -o "$WORKDIR/$name"
  fi
}
fetch guard.py
fetch check-guard.py

SKILL="$WORKDIR/skill"
mkdir -p "$SKILL/references"
if [[ -f "$HERE/../skills/ferret9/SKILL.md" ]]; then
  cp -R "$HERE/../skills/ferret9/." "$SKILL/"
else
  curl -fsSL "$REPO/skills/ferret9/SKILL.md" -o "$SKILL/SKILL.md"
  curl -fsSL "$REPO/skills/ferret9/references/task-to-credential.md" -o "$SKILL/references/task-to-credential.md"
  curl -fsSL "$REPO/skills/ferret9/references/detail-writing-guide.md" -o "$SKILL/references/detail-writing-guide.md"
fi

SRC="$WORKDIR/guard.py"
MARK="ferret9-guard"
REASON="凭据只能走 ferret9。先跑 ferret9 list 选凭据，再用 ferret9 run <名称> -- <命令>。"

want="${1:-all}"
case "$want" in
  all|cursor|claude|codex|hermes|copilot|qoder|lingma|trae|codebuddy|kimi) ;;
  *) echo "不认识的 agent：$want" >&2; exit 2 ;;
esac

installed=0
skipped=0
failed=0
note() { printf '  %s\n' "$1"; }

run_check() {
  local name="$1" script="$2"
  local out rc
  set +e
  out="$("$PY" "$WORKDIR/check-guard.py" "$name" "$script" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    note "$name 验证通过"
  else
    note "$name 验证失败"
    printf '%s\n' "$out" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
}

place_script() {
  local dir="$1"
  mkdir -p "$dir"
  cp "$SRC" "$dir/ferret9-guard.py"
  chmod 755 "$dir/ferret9-guard.py"
  printf '%s' "$dir/ferret9-guard.py"
}

place_skill() {
  local dir="$1"
  mkdir -p "$dir"
  cp -R "$SKILL/." "$dir/"
}

# --- Cursor ------------------------------------------------------------- 
# ~/.cursor/hooks.json uses beforeReadFile and beforeShellExecution.
# A crash or timeout only blocks when failClosed is true.
if [[ "$want" == all || "$want" == cursor ]]; then
  if [[ -d "$HOME/.cursor" ]]; then
    script="$(place_script "$HOME/.cursor/hooks")"
    place_skill "$HOME/.cursor/skills/ferret9"
    "$PY" - "$HOME/.cursor/hooks.json" "$script" <<'PY'
import json, os, sys
path, script = sys.argv[1], sys.argv[2]
try:
    doc = json.load(open(path))
except FileNotFoundError:
    doc = {}
if not isinstance(doc, dict):
    sys.exit("hooks.json 不是对象")
doc.setdefault("version", 1)
hooks = doc.setdefault("hooks", {})
entry = {"command": "python3 " + script + " cursor", "failClosed": True, "_ferret9": True}
for event in ("beforeReadFile", "beforeShellExecution"):
    group = [h for h in hooks.get(event, []) if not h.get("_ferret9")]
    group.append(entry)
    hooks[event] = group
json.dump(doc, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
    run_check cursor "$script"
    installed=$((installed + 1))
  else
    note "cursor 未安装，跳过"; skipped=$((skipped + 1))
  fi
fi

# --- shared JSON shape: {hooks:{PreToolUse:[{matcher,hooks:[...]}]}} ---- 
json_agent() {
  local name="$1" dir="$2" file="$3" matcher="$4"
  if [[ ! -d "$dir" ]]; then note "$name 未安装，跳过"; skipped=$((skipped + 1)); return; fi
  local script
  script="$(place_script "$dir/hooks")"
  place_skill "$dir/skills/ferret9"
  "$PY" - "$dir/$file" "$script" "$matcher" "$name" <<'PY'
import json, sys
path, script, matcher, name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
try:
    doc = json.load(open(path))
except FileNotFoundError:
    doc = {}
if not isinstance(doc, dict):
    sys.exit(path + " 不是对象")
groups = doc.setdefault("hooks", {}).setdefault("PreToolUse", [])
groups[:] = [g for g in groups if not any(h.get("_ferret9") for h in g.get("hooks", []))]
groups.append({"matcher": matcher, "hooks": [
    {"type": "command", "command": "python3 " + script + " " + name, "timeout": 10, "_ferret9": True}]})
json.dump(doc, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
  run_check "$name" "$script"
  installed=$((installed + 1))
}

if [[ "$want" == all || "$want" == claude ]]; then
  json_agent claude "$HOME/.claude" settings.json "Read|Bash"
fi
if [[ "$want" == all || "$want" == qoder ]]; then
  json_agent qoder "$HOME/.qoder" settings.json "Read|Bash"
fi
if [[ "$want" == all || "$want" == lingma ]]; then
  json_agent lingma "$HOME/.lingma" settings.json "Read|Bash"
fi
if [[ "$want" == all || "$want" == codebuddy ]]; then
  json_agent codebuddy "$HOME/.codebuddy" settings.json "Read|Bash"
fi

# --- TRAE: ~/.trae-cn/hooks.json, shell tool is RunCommand --------------- 
if [[ "$want" == all || "$want" == trae ]]; then
  if [[ -d "$HOME/.trae-cn" || -d "$HOME/.trae" ]]; then
    base="$HOME/.trae-cn"
    [[ -d "$base" ]] || base="$HOME/.trae"
    script="$(place_script "$base/hooks")"
    place_skill "$base/skills/ferret9"
    "$PY" - "$base/hooks.json" "$script" <<'PY'
import json, sys
path, script = sys.argv[1], sys.argv[2]
try:
    doc = json.load(open(path))
except FileNotFoundError:
    doc = {}
doc.setdefault("version", 1)
groups = doc.setdefault("hooks", {}).setdefault("PreToolUse", [])
groups[:] = [g for g in groups if not any(h.get("_ferret9") for h in g.get("hooks", []))]
groups.append({"matcher": "Read|RunCommand", "hooks": [
    {"type": "command", "command": "python3 " + script + " trae", "timeout": 10, "_ferret9": True}]})
json.dump(doc, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
    run_check trae "$script"
    installed=$((installed + 1))
  else
    note "trae 未安装，跳过"; skipped=$((skipped + 1))
  fi
fi

# --- GitHub Copilot CLI: events are camelCase ---------------------------- 
if [[ "$want" == all || "$want" == copilot ]]; then
  if [[ -d "$HOME/.copilot" ]]; then
    script="$(place_script "$HOME/.copilot/hooks")"
    place_skill "$HOME/.copilot/skills/ferret9"
    "$PY" - "$HOME/.copilot/hooks.json" "$script" <<'PY'
import json, sys
path, script = sys.argv[1], sys.argv[2]
try:
    doc = json.load(open(path))
except FileNotFoundError:
    doc = {}
doc.setdefault("version", 1)
groups = doc.setdefault("hooks", {}).setdefault("preToolUse", [])
groups[:] = [g for g in groups if not any(h.get("_ferret9") for h in g.get("hooks", []))]
groups.append({"matcher": "read_file|view|bash", "hooks": [
    {"type": "command", "command": "python3 " + script + " copilot", "timeout": 10, "_ferret9": True}]})
json.dump(doc, open(path, "w"), indent=2, ensure_ascii=False)
open(path, "a").write("\n")
PY
    run_check copilot "$script"
    installed=$((installed + 1))
  else
    note "copilot 未安装，跳过"; skipped=$((skipped + 1))
  fi
fi

# --- TOML agents: Codex, Hermes, Kimi ------------------------------------ 
toml_agent() {
  local name="$1" dir="$2" file="$3" block="$4"
  if [[ ! -d "$dir" ]]; then note "$name 未安装，跳过"; skipped=$((skipped + 1)); return; fi
  local script dest="$dir/$file"
  script="$(place_script "$dir/hooks")"
  place_skill "$dir/skills/ferret9"
  "$PY" - "$dest" "$script" "$block" "$name" <<'PY'
import pathlib, sys
dest, script, kind, name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
p = pathlib.Path(dest)
text = p.read_text() if p.exists() else ""
start = "# >>> ferret9-guard >>>"
end = "# <<< ferret9-guard <<<"
if start in text and end in text:
    text = text[:text.index(start)] + text[text.index(end) + len(end):]
text = text.rstrip() + "\n"
if kind == "codex":
    body = f"""
{start}
[permissions.filesystem]
"~/.kube" = "deny"
"~/.aliyun" = "deny"
"~/.aws" = "deny"
"~/.ssh" = "deny"
"~/.cloudflare" = "deny"
"~/.config/gh" = "deny"
"~/.ossutilconfig" = "deny"
"~/.netrc" = "deny"

[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "python3 {script} {name}"
timeout = 10
{end}
"""
elif kind == "hermes":
    body = f"""
{start}
hooks:
  pre_tool_call:
    - matcher: "read_file|terminal"
      command: "python3 {script} {name}"
      timeout: 10
      fail_closed: true
{end}
"""
else:
    body = f"""
{start}
[[hooks]]
event = "PreToolUse"
matcher = "Read|Bash"
command = "python3 {script} {name}"
timeout = 10
{end}
"""
p.write_text(text + body)
PY
  run_check "$name" "$script"
  installed=$((installed + 1))
}

if [[ "$want" == all || "$want" == codex ]]; then
  toml_agent codex "$HOME/.codex" config.toml codex
fi
if [[ "$want" == all || "$want" == hermes ]]; then
  toml_agent hermes "$HOME/.hermes" config.yaml hermes
fi
if [[ "$want" == all || "$want" == kimi ]]; then
  toml_agent kimi "$HOME/.kimi-code" config.toml kimi
fi

place_skill "$HOME/.agents/skills/ferret9"

echo
echo "安装 $installed 个，跳过 $skipped 个，验证失败 $failed 个。skill 已写入 ~/.agents/skills/ferret9，以及每个装上的 agent 的 skills/ferret9。"
if [[ "$failed" -ne 0 ]]; then exit 1; fi
