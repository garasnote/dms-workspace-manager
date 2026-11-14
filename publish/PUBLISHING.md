# Publishing this plugin in the DMS plugin registry

DMS installs plugins from `duxlabs-dev/dux-plugin-registry`
(`dms plugins install <id>`), and the directory at https://plugins.duxlabs.dev
is built from it. Getting listed is a pull request against that repo plus a
public git repo for the plugin.

## 0. What the plugin needs before it is submittable

- `plugin.json` `id` and `name` must match the registry entry exactly.
  Currently: id `workspaceManager`, name `Niri Workspace Manager`.
- A public repo with the plugin files at the root (`LICENSE`, `README.md`,
  `plugin.json`, the `*.qml` files, `templates.json`).
- `README.md` — done.
- `LICENSE` — done (MIT-0: no attribution required). The registry does not
  validate or even look at the license, so any license works; DMS itself ships
  MIT, which is why MIT was the starting point.
- `screenshot.png` in the repo root. **Required**: `validate_links.py` rejects
  an entry without a reachable `screenshot` URL. Take it with the dash open on a
  neutral workspace, then crop it to the popout:

  ```bash
  grim -o eDP-1 /tmp/shot.png
  python3 -c "from PIL import Image; Image.open('/tmp/shot.png').crop((470,40,1160,880)).save('screenshot.png')"
  ```

## 1. Create the public plugin repo

From this directory:

```bash
gh repo create garasnote/dms-workspace-manager --public --source=. --remote=origin \
  --description "Niri workspace manager plugin for Dux Modular Shell"
git push -u origin HEAD
```

Adjust the name if you prefer something else (`dms-niri-workspaces`, ...), then
update `publish/registry-entry.json`'s `repo` and `screenshot` accordingly.

## 2. Fork the registry and add the entry

```bash
gh repo fork duxlabs-dev/dux-plugin-registry --clone --default-branch-only
cd dux-plugin-registry
cp /path/to/publish/registry-entry.json plugins/garasnote-workspace-manager.json
```

File naming is `plugins/{github-username}-{plugin-name}.json`, lowercase with
hyphens.

Field rules (from the registry docs):

| Field | Value here |
|-------|------------|
| `id`, `name` | must match `plugin.json` |
| `capabilities` | only registry types: `daemon`, `dash-tab`, `launcher` |
| `category` | one of `utilities`, `monitoring`, `system`, `appearance`, `productivity`, `media`, `networking` → `utilities` |
| `repo` | public repo URL |
| `path` | only for monorepos |
| `dependencies` | `["niri"]` |
| `compositors` | `["niri"]` (this plugin is niri-only) |
| `distro` | `["any"]` |
| `screenshot` | direct image URL |
| `requires_dms` | `>=2.1.0` (developed and tested on 2.1.2) |

Notes from reading the registry's own validators:

- `.github/generate.py --validate` requires exactly: `id`, `name`,
  `capabilities`, `category`, `repo`, `author`, `description`, `dependencies`,
  `compositors`, `distro`. `id` must match `^[a-z][a-zA-Z0-9]*$`.
- `.github/validate_links.py` additionally requires a **resolvable**
  `screenshot` URL and a resolvable `repo` URL, so both must exist before the
  PR is opened.
- License is not a registry field at all; it lives in the plugin repo only.

## 3. Validate, then open the PR

```bash
python3 .github/generate.py --validate
python3 .github/validate_links.py
git checkout -b add-workspace-manager
git add plugins/garasnote-workspace-manager.json
git commit -m "Add workspaceManager (Niri Workspace Manager)"
git push -u origin add-workspace-manager
gh pr create --repo duxlabs-dev/dux-plugin-registry \
  --title "Add workspaceManager: Niri Workspace Manager" \
  --body "Plugin: <repo URL>

Composite plugin (daemon + dash tab + launcher) for niri: create/rename/focus
workspaces, diff-aware app templates, session snapshot with confirm, emoji
labels in the bar workspace indicator. Requires DMS >= 2.1.0."
```

## 4. After merge

- A tracking issue is opened automatically: that is where users 👍 upvote
  (the directory ranks by upvotes) and where maintainers flag
  `/reviewed`, `/broken`, `/unmaintained`, `/deprecated`.
- Users install with `dms plugins install workspaceManager`, or from
  Settings → Plugins → Discover.
- Updates: push a new `version` in `plugin.json`; `dms plugins update` picks it
  up and `~/.config/dms/plugins.lock.json` pins the commit.
- Translations (optional, later): every string must already go through
  `I18n.trFor("workspaceManager", "...")`, then a follow-up PR setting
  `"i18n": true` in the registry entry applies to join the POEditor project.
  This plugin currently uses plain strings, so that is a separate pass.

## Other routes

- **First-party plugins** live in `duxlabs-dev/dux-plugins` and are maintained
  by Dux Labs; that is by invitation, not a PR.
- **Example plugins** live in `dux-shell/quickshell/PLUGINS/`. A niri-only
  composite is unlikely to be accepted there, but the dash editor patterns in
  `WorkspaceDash.qml` are reusable examples if you want to upstream anything.
- **Private/personal use** needs no registry at all: the plugin already works
  from `~/.config/dms/plugins/workspaceManager`. A private repo can be added
  with `dms registry add <name> <git-url>` if you later want that.
