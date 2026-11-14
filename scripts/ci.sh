#!/usr/bin/env bash
# The checks CI runs, runnable here first. Same script in both places on purpose:
# a pipeline that only exists in YAML tends to rot.
#
#   ./scripts/ci.sh                      # uses DUX_SHELL_DIR, default /tmp/dux-shell-master
#   DUX_SHELL_DIR=~/src/dux-shell ./scripts/ci.sh
#
# What is deliberately NOT here: anything that needs a running compositor. The
# real behaviour of this plugin requires niri, a live DMS shell and a clipboard,
# so the benchmark and the smoke tests stay manual (see bench/ and README).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

DUX_SHELL_DIR="${DUX_SHELL_DIR:-/tmp/dux-shell}"
QML_IMPORT_DIR="${QML_IMPORT_DIR:-/usr/lib/qt6/qml}"
fail=0
step() { printf '\n== %s\n' "$*"; }
bad() { printf '  FAIL: %s\n' "$*"; fail=1; }
ok() { printf '  ok: %s\n' "$*"; }

# ---------------------------------------------------------------- 1. QML syntax
# qmllint needs the shell's own modules to resolve `import qs.*`. It reports
# nothing useful for a syntax error (just a non-zero exit), so the exit code is
# the signal and the file name is the message.
step "qmllint"
if command -v qmllint >/dev/null 2>&1; then
  if [[ ! -d "$DUX_SHELL_DIR/quickshell" ]]; then
    bad "DUX_SHELL_DIR=$DUX_SHELL_DIR has no quickshell/ directory; cannot resolve qs.* imports"
  else
    for f in ./*.qml; do
      if out=$(qmllint -I "$DUX_SHELL_DIR/quickshell" -I "$QML_IMPORT_DIR" "$f" 2>&1); then
        :
      else
        bad "$f"
        if [[ -n "$out" ]]; then
          printf '%s\n' "$out" | head -20 | sed 's/^/    /'
        else
          printf '    qmllint exited non-zero with no diagnostic (it does that for syntax errors)\n'
        fi
      fi
    done
    ok "$(ls -1 ./*.qml | wc -l) QML files parsed"
  fi
else
  bad "qmllint not found (Arch: qt6-declarative, Debian: qt6-declarative-dev-tools)"
fi

# ------------------------------------------------- 2. manifests and data files
step "manifests, settings contract, templates"
python3 - <<'PY' || fail=1
import json, os, re, sys

problems = []
def need(cond, msg):
    if not cond:
        problems.append(msg)

def load(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except Exception as exc:  # noqa: BLE001 - report, don't crash the pipeline
        problems.append(f"{path}: not valid JSON ({exc})")
        return None

plugin = load("plugin.json")
settings_src = open("WorkspaceSettings.qml").read() if os.path.exists("WorkspaceSettings.qml") else ""

if plugin:
    for key in ("id", "name", "description", "version", "author", "license", "type"):
        need(isinstance(plugin.get(key), str) and plugin[key].strip(), f"plugin.json: missing/empty '{key}'")
    need(re.fullmatch(r"\d+\.\d+\.\d+", plugin.get("version", "")), "plugin.json: version must be semver (x.y.z)")
    # not "id == directory": CI checks out into the repo name, which differs from
    # the plugin id by design (dms-workspace-manager holds plugin id workspaceManager)
    need(re.fullmatch(r"[a-z][A-Za-z0-9]*", plugin.get("id", "")), "plugin.json: id must be camelCase alphanumeric")
    if plugin.get("id") != os.path.basename(os.getcwd()):
        print(f"  note: id '{plugin.get('id')}' differs from directory '{os.path.basename(os.getcwd())}' (fine outside the plugin dir)")
    need("requires_dms" in plugin, "plugin.json: missing requires_dms")
    comps = plugin.get("components", {})
    for name, rel in comps.items():
        need(os.path.exists(rel), f"plugin.json: component '{name}' points at missing {rel}")
    for key in ("settings",):
        rel = plugin.get(key)
        if rel:
            need(os.path.exists(rel), f"plugin.json: '{key}' points at missing {rel}")
    for cap in plugin.get("capabilities", []):
        need(bool(cap.strip()), "plugin.json: empty capability")

# every setting key the UI declares must carry a default, or the daemon reads None
keys = re.findall(r'settingKey:\s*"([^"]+)"', settings_src)
blocks = re.split(r'\n\s*ToggleSetting\s*\{|\n\s*(?:Slider|Number|Text|Dropdown)Setting\s*\{', settings_src)[1:]
for key, block in zip(keys, blocks):
    need("defaultValue:" in block, f"WorkspaceSettings.qml: setting '{key}' has no defaultValue")

templates = load("templates.json")
if templates is not None:
    need(templates.get("version") == 1, "templates.json: expected version 1")
    items = templates.get("templates")
    need(isinstance(items, list) and items, "templates.json: 'templates' must be a non-empty list")
    for t in items or []:
        need(bool(t.get("name")), "templates.json: a template has no name")
        apps = t.get("apps")
        need(isinstance(apps, list) and apps, f"templates.json: '{t.get('name')}' has no apps")
        for app in apps or []:
            if isinstance(app, str):
                need(bool(app.strip()), f"templates.json: '{t.get('name')}' has an empty app string")
            else:
                need(bool(app.get("cmd")), f"templates.json: '{t.get('name')}' has an app without cmd")

entry = load("publish/registry-entry.json")
if entry and plugin:
    need(entry.get("id") == plugin.get("id"), "publish/registry-entry.json: id differs from plugin.json")
    need(entry.get("name") == plugin.get("name"), "publish/registry-entry.json: name differs from plugin.json")
    need(entry.get("requires_dms") == plugin.get("requires_dms"), "publish/registry-entry.json: requires_dms differs from plugin.json")
    need(entry.get("author") == plugin.get("author"), "publish/registry-entry.json: author differs from plugin.json")
    need(str(entry.get("repo", "")).startswith("https://github.com/"), "publish/registry-entry.json: repo must be a github URL")
    need(str(entry.get("screenshot", "")).endswith(".png"), "publish/registry-entry.json: screenshot must be a .png URL")

for p in problems:
    print(f"  FAIL: {p}")
print(f"  ok: {len(keys)} settings keys, {len((templates or {}).get('templates', []))} templates, manifests consistent")
sys.exit(1 if problems else 0)
PY

# ------------------------------------------------------------------ 3. shell
step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -S warning bench/*.sh scripts/*.sh; then
    ok "scripts clean at warning level"
  else
    bad "shellcheck reported findings"
  fi
else
  printf '  skipped: shellcheck not installed (CI installs it)\n'
fi

# --------------------------------------------------- 4. leftovers and hygiene
step "hygiene"
# console.warn/error are how the daemon reports real failures (unparseable
# templates.json, a failed spawn) and stay; console.log and the "[wsm]" debug tag
# used during development do not.
if grep -nE 'console\.log\(' ./*.qml >/tmp/ci-console.txt 2>/dev/null; then
  bad "console.log left in QML:"
  sed 's/^/    /' /tmp/ci-console.txt
else
  ok "no console.log in QML"
fi
if grep -n '\[wsm\]' ./*.qml >/tmp/ci-wsm.txt 2>/dev/null; then
  bad "development debug tags left in QML:"
  sed 's/^/    /' /tmp/ci-wsm.txt
else
  ok "no [wsm] debug tags"
fi

if grep -rn 'TODO\|FIXME\|XXX' ./*.qml >/tmp/ci-todo.txt 2>/dev/null; then
  printf '  note: TODOs present\n'
  sed 's/^/    /' /tmp/ci-todo.txt
fi

for f in ./*.qml; do
  if grep -qP '\t' "$f"; then bad "$f: tab characters (QML house style is spaces)"; fi
done
ok "indentation check done"

printf '\n'
if (( fail )); then
  printf 'ci: FAILED\n'
  exit 1
fi
printf 'ci: passed\n'
