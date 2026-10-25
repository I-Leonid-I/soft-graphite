# Installing Soft Graphite — guide for an AI agent (and for humans)

You are installing a KDE Plasma 6 desktop theme **with behaviour**: native KWin effects,
a KWin script, plasmoids, user services, session environment and app patchers.
Work step by step, verify each step, and tell the user plainly what was and was not verified.
Talk to the user in their language.

`REPO` below is the cloned repository, `SG=~/.local/share/soft-graphite`.

## 0. Rules (read first, they come from real crashes)

1. **Never unload/reload the native KWin effects live** (`qdbus6 org.kde.KWin /Effects unloadEffect|loadEffect softgraphite_*`).
   On Wayland this crashes `kwin_wayland` and closes every application. New native builds take effect at the **next login**.
2. **Never overwrite a loaded `.so` in place.** Copy to a temp name and `mv` over it (the scripts do this).
   Overwriting a library mmapped by KWin/plasmashell crashes them.
3. **Never replace the user's config files wholesale.** Merge keys with `tools/merge-kconfig.py`.
   Before touching anything, back up: `~/.config/{kwinrc,kdeglobals,kglobalshortcutsrc,kwinrulesrc,plasma-org.kde.plasma.desktop-appletsrc,plasmashellrc,klaunchrc,plasmanotifyrc}`, `~/.config/gtk-3.0`, `~/.config/gtk-4.0`.
4. **Ask before closing or restarting the user's applications**, before logging out, and before running
   `plasma-layout.js` (it deletes all existing panels).
5. Do not modify `/usr`, `/opt`, `/etc` except the optional pacman hook (step 9), and only with the user's consent
   (it needs `sudo`; let the user run sudo commands themselves).
6. `qdbus6 org.kde.KWin /KWin reconfigure` does **not** reload running KWin JS scripts. The fullscreen script
   is (re)loaded by `$SG/start-kwin.py`, which also runs on every login via `soft-graphite-edge.service`.
7. Do not run interactive KWin scripts (window picker, crosshair cursor) without warning the user: Esc cancels.

## 1. Check the system

- Arch Linux or CachyOS, **Plasma 6.8 or newer**, **Wayland** session (`echo $XDG_SESSION_TYPE` → `wayland`).
- `kwin_wayland --version`, `plasmashell --version`, `qmake6 -v` — note them for the report.
- Monitors: `kscreen-doctor -o`. The theme is tuned for 1920×1080 at 100% but works with any layout.
- Ask the user which optional parts they want (step 8): ChatGPT/Codex, Antigravity, Claude Desktop,
  VS Code, JetBrains IDEs, Chrome, faster DDC/CI brightness.

## 2. Packages

Ask the user to run (it needs sudo):

```bash
sudo pacman -S --needed base-devel cmake ninja extra-cmake-modules pkgconf python rsync \
  qt6-base qt6-declarative qt6-wayland layer-shell-qt kwin kdecoration libplasma plasma-workspace \
  kcoreaddons kconfig ksvg kwindowsystem kvantum ttf-fira-sans libdbusmenu-gtk3 libxcb dbus
```

KWin development headers are part of the `kwin` package on Arch (`/usr/include/kwin`).

## 3. Copy files

```bash
cd REPO
SG=~/.local/share/soft-graphite
mkdir -p "$SG" ~/.local/share/{plasma/look-and-feel,plasma/desktoptheme,plasma/plasmoids,color-schemes,aurorae/themes,icons,kwin/scripts,kwin/effects,wallpapers/SoftGraphite} ~/.config/Kvantum

# core: helpers, patchers, native sources (scripts find each other by these paths)
rsync -a core/ "$SG/"

# appearance
rsync -a theme/plasma/look-and-feel/ ~/.local/share/plasma/look-and-feel/
rsync -a theme/plasma/desktoptheme/ ~/.local/share/plasma/desktoptheme/
cp theme/color-schemes/*.colors ~/.local/share/color-schemes/
rsync -a theme/aurorae/ ~/.local/share/aurorae/themes/
rsync -a theme/kvantum/ ~/.config/Kvantum/
rsync -a theme/icons/ ~/.local/share/icons/
cp theme/wallpapers/*.png ~/.local/share/wallpapers/SoftGraphite/

# plasmoids and KWin
rsync -a plasmoids/ ~/.local/share/plasma/plasmoids/
rsync -a kwin/scripts/ ~/.local/share/kwin/scripts/
rsync -a kwin/effects/ ~/.local/share/kwin/effects/
```

### Theme only (no native parts)
If the user wants only the look: do the "appearance" block above, then
`plasma-apply-lookandfeel -a org.leonid.softgraphite.dark` and set the decoration to the plain Aurorae theme,
because the look-and-feel default expects the native decoration plugin from step 4:

```bash
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__SoftGraphiteUnified
qdbus6 org.kde.KWin /KWin reconfigure
```
Window buttons will then be on the right, and there are no panels, dock, fullscreen behaviour or animations.
Stop here.

## 4. Build the native parts

```bash
bash REPO/tools/build-once.sh          # edge helper, appmenu bridge, dock modules, decoration, GTK menu module
python3 ~/.local/share/soft-graphite/rebuild-all.py --no-reload   # KWin effects, applets, panel tools
```

Expected result (check that each file exists):
- `~/.local/lib/qt6/plugins/kwin/effects/plugins/softgraphite_{corners,layers_v10,outline_resize}.so`
- `~/.local/lib/qt6/plugins/plasma/applets/org.leonid.softgraphite.{tray,appmenu,notifications}.so`
- `~/.local/lib/qt6/plugins/org.kde.kdecoration3/liborg.leonid.softgraphite.aurorae_pair.so`
- `~/.local/share/kwin/shaders/shapecorners{,_core}.frag`
- `~/.local/share/plasma/plasmoids/org.leonid.softgraphite.{appmenu,dock,keyboard}/contents/ui/panelnative/libGraphitePanelTools.so`
- `$SG/soft-graphite-edge`, `$SG/appmenu-bridge`, `$SG/last-built-version.json`

If a compile error mentions a KWin/Plasma API: the sources were written for Plasma 6.8. Fix the source
minimally for the newer API, rebuild, and tell the user what you changed. `rebuild-all.py` never installs
a facade that lacks Qt plugin metadata.

## 5. Session environment and services

```bash
cd REPO
mkdir -p ~/.config/environment.d ~/.config/plasma-workspace/env ~/.config/systemd/user
cp env/environment.d/*.conf ~/.config/environment.d/
cp env/plasma-workspace/*.sh ~/.config/plasma-workspace/env/
cp systemd/soft-graphite-edge.service systemd/soft-graphite-appmenu.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable soft-graphite-edge.service soft-graphite-appmenu.service
```

- `QT_PLUGIN_PATH` (60-…) makes KWin/plasmashell find the user-local plugins. `GTK_PATH`/`GTK_MODULES` (90-…)
  load the GTK 3 global menu module. The Java file (65-…) is only needed for JetBrains IDEs (step 8).
- `soft-graphite-edge` (D-Bus `org.leonid.SoftGraphite`) drives panels in fullscreen. Its `ExecStartPost`
  runs `start-kwin.py`: rebuilds natives if KWin/Plasma/Qt changed, loads the fullscreen script and the effects.
- Do **not** start these services now if the user is working. They start at the next login.

## 6. Merge settings

```bash
cd REPO
for f in kwinrc kdeglobals klaunchrc plasmanotifyrc softgraphite-dockrc; do
  python3 tools/merge-kconfig.py config/$f.ini $f
done
python3 tools/merge-kconfig.py config/kvantum.kvconfig.ini ~/.config/Kvantum/kvantum.kvconfig
python3 tools/merge-kconfig.py config/kwinrulesrc.ini kwinrulesrc
```

Then:
- **Window rules:** append the four rule names to `Order=` in `[General]` of `~/.config/kwinrulesrc`
  (comma-separated, keep existing names first; older files also have `rules=` and `count=` — update those too),
  then `qdbus6 org.kde.KWin /KWin reconfigure`.
- **Fonts:** `mkdir -p ~/.config/fontconfig/conf.d && cp config/60-soft-graphite-ui.conf ~/.config/fontconfig/conf.d/`
- **GTK:** `cp config/gtk-3.0/soft-graphite-frame.css ~/.config/gtk-3.0/` and make sure `~/.config/gtk-3.0/gtk.css`
  contains the line `@import url("soft-graphite-frame.css");` (append it; KDE regenerates the rest).
  Window buttons: `kwriteconfig6 --file ~/.config/gtk-3.0/settings.ini --group Settings --key gtk-decoration-layout ":"`
  and the same for `~/.config/gtk-4.0/settings.ini`.
- **Shortcuts** (`config/kglobalshortcutsrc.ini`): kglobalaccel owns that file while running. Set them in
  System Settings → Shortcuts instead: remove KWin's `Quick Tile Window to the Top/Left/Right/Bottom`
  (Meta+arrows; the theme's script uses Meta+Up/Left/Right), and give Spectacle "Capture rectangular region"
  `Meta+Shift+S`. `Meta+Ctrl+F` is registered by the script.
- **Appearance:** `plasma-apply-lookandfeel -a org.leonid.softgraphite.dark`
  (light: `org.leonid.softgraphite.light`; the brightness tray's "Dark mode" toggle switches between them).
- **Wallpaper:** `plasma-apply-wallpaperimage ~/.local/share/wallpapers/SoftGraphite/graphite-folds.png`
- **Applications launcher icon / busy cursor / notifications position** come from the merged files.

## 7. Panels

**Ask the user first: this deletes all their current panels.** Then:

```bash
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat REPO/config/plasma-layout.js)"
```

Verify on **every** monitor (screenshot, or panel Edit Mode): a 60 px floating dock at the bottom center,
a 32 px capsule top-left (launcher + app menu), a 32 px capsule top-right (tray, layout, clock); each panel
floating, "Fit content", visibility "Windows go below". Fix any that differ in Edit Mode.
Tray: in its settings keep network, volume, battery and notifications always shown; the rest under the arrow.
Pinned dock apps are shared by all docks and stored in `~/.config/softgraphite-dockrc`.

Known machine-specific detail: `soft-graphite-edge` (`core/native/edge/main.cpp`, `panelMode`) re-applies
"Windows go below" to the author's panel IDs. On other machines it simply finds no such panels — harmless.

## 8. Optional parts

Each part is independent. Install only what the user has and wants. After copying a `.desktop` file,
replace the placeholder: `sed -i "s|@HOME@|$HOME|g" ~/.local/share/applications/<file>.desktop`.
Apps keep working unpatched if a patch no longer matches a new version: the launchers fall back to the original.

**ChatGPT / Codex** (AUR `chatgpt-desktop-bin`, `/usr/lib/chatgpt`): native KDE frame and global menu.
`cp REPO/bin/chatgpt ~/.local/bin/`, `cp REPO/applications/chatgpt.desktop ~/.local/share/applications/`,
copy `systemd/codex-autopatch.{path,service}` and `systemctl --user enable --now codex-autopatch.path`.
First run `python3 $SG/rebuild-codex.py` (creates the patched copy in `$SG/apps/chatgpt-menu`).
Needs `$SG/native/chatgpt-menu/menu-bridge` from `build-once.sh`. Runs through XWayland.

**Antigravity** (`/opt/Antigravity`): `bin/antigravity`, `applications/antigravity.desktop`,
`systemd/antigravity-autopatch.*`, then `python3 $SG/rebuild-antigravity.py`.

**Claude Desktop** (`/usr/lib/claude-desktop`): `bin/claude-desktop`, `systemd/claude-autopatch.*`,
`python3 $SG/rebuild-claude.py --if-stale`. Claude's own desktop entry runs `claude-desktop` from `PATH`,
so `~/.local/bin` must come before `/usr/bin` in the session `PATH` (same for the `code` wrapper).

**VS Code** (`/usr/bin/code`): `bin/code` (XWayland for the global menu, always opens as a centered window)
and `applications/com.microsoft.VSCode.UrlHandler.desktop`; merge `config/vscode-settings.json`
into `~/.config/Code/User/settings.json`. Note: the wrapper assumes 1920 px wide monitors side by side
when choosing the monitor; adjust the two `1920` constants for other layouts.

**JetBrains IDEs**: install the plugin "Global Menu and Decoration" (`io.gitlab.jfronny.globalmenu`, by JFronny)
from the Marketplace in the IDE, then copy its plugin folder (`~/.local/share/JetBrains/<IDE>/globalmenu`) to
`$SG/plugins/globalmenu`, copy `systemd/jetbrains-plugin-sync.*`, enable the `.path` unit, and run
`python3 $SG/sync-jetbrains-plugins.py`. The patcher (`native/jetbrains-globalmenu/patch-globalmenu.py`) needs
`javac` (JDK, or an IDE's bundled JBR) and only replaces classes it recognises (plugin 1.4.1).
Copy `env/environment.d/65-soft-graphite-java.conf` and `env/plasma-workspace/65-soft-graphite-java.sh` for
server-side window frames. `native/jetbrains-windows` is an advanced, IDEA-Flatpak-only adapter bound to exact
class hashes — skip it unless the user asks.

**Chrome** (system frame, links raise the browser): copy `/usr/share/applications/google-chrome.desktop` to
`~/.local/share/applications/` and prefix every `Exec=` with
`$HOME/.local/share/soft-graphite/browser-open.py google-chrome google-chrome -- ` (absolute path, no `$HOME`).
In Chrome: Settings → Appearance → "Use system title bar and borders".
Flatpak browsers: `cp REPO/flatpak/global ~/.local/share/flatpak/overrides/global` only if that file does not
exist yet (otherwise merge the `[Session Bus Policy]` line).

**Faster external-monitor brightness (DDC/CI)**: advanced, skip unless asked. Build `libpowerdevilcore` from the
KDE `powerdevil` tag matching the installed package with `core/native/powerdevil/ddc-responsive.patch`
(see its `README.txt`), put it into a user-local directory, adjust that directory in `launch.sh`, record
`sha256sum /usr/lib/org_kde_powerdevil /usr/lib/libpowerdevilcore.so.<version> > $SG/native/powerdevil/system.sha256`
and install `systemd/plasma-powerdevil.service.d/`. Without a matching `system.sha256` the launcher uses the
system PowerDevil.

## 9. Rebuild after updates

`start-kwin.py` already rebuilds at login when KWin/Plasma/Qt versions change. Additionally offer the pacman hook
(the user runs it):

```bash
sed "s|@USER@|$USER|; s|@HOME@|$HOME|" REPO/core/99-softgraphite.hook | sudo tee /etc/pacman.d/hooks/99-softgraphite.hook
```

`build-once.sh` parts (decoration, dock modules, edge helper) are not rebuilt automatically; rerun it after a
major Plasma upgrade if the window decoration or dock fails to load.

## 10. Apply and verify

1. Ask the user to save their work, then **log out and back in** (this is what loads the native effects safely).
2. Verify, on **both/all monitors**, with screenshots and logs — not by assumption:
   - `systemctl --user status soft-graphite-edge soft-graphite-appmenu` — active, no errors;
     `journalctl --user -u soft-graphite-edge -b` — no "could not be loaded".
   - `qdbus6 org.kde.KWin /Effects isEffectLoaded softgraphite_corners` (and `softgraphite_layers_v10`,
     `softgraphite_outline_resize`) → `true`.
   - `qdbus6 org.kde.KWin /Scripting isScriptLoaded soft-graphite-fullscreen` → `true`.
   - Windows: rounded 12 px corners, buttons on the left, open centered and windowed.
   - Maximize button → fullscreen on that monitor; bottom edge shows the dock; top-left corner shows the left capsule.
   - Global menu of Dolphin/Konsole appears in the top-left capsule.
   - Idle CPU of `soft-graphite-edge` and `appmenu-bridge` ≈ 0% (`top -b -n1 | grep -E 'edge|appmenu'`).
3. Report: what is installed, what was verified and how, what was skipped or could not be verified.

## Uninstall / rollback

1. `systemctl --user disable --now soft-graphite-edge soft-graphite-appmenu *-autopatch.path jetbrains-plugin-sync.path`
2. `plasma-apply-lookandfeel -a org.kde.breezedark.desktop`; restore the backed-up config files from step 0
   (log out first for `kglobalshortcutsrc`).
3. Remove `~/.config/environment.d/*soft-graphite*`, `~/.config/plasma-workspace/env/*soft-graphite*`,
   the installed files listed in step 3–4, `~/.local/bin/{chatgpt,antigravity,claude-desktop,code}` wrappers,
   and `/etc/pacman.d/hooks/99-softgraphite.hook` (sudo).
4. Log out and back in.

## Map: where things live

| Component | Installed to |
|---|---|
| Global themes | `~/.local/share/plasma/look-and-feel/org.leonid.softgraphite.{dark,light}` |
| Plasma theme, colors, Kvantum, Aurorae, icons | `~/.local/share/plasma/desktoptheme/`, `~/.local/share/color-schemes/`, `~/.config/Kvantum/`, `~/.local/share/aurorae/themes/`, `~/.local/share/icons/` |
| Plasmoids | `~/.local/share/plasma/plasmoids/org.leonid.softgraphite.*` (+ facades in `~/.local/lib/qt6/plugins/plasma/applets/`) |
| KWin script / JS effects | `~/.local/share/kwin/scripts/soft-graphite-fullscreen`, `~/.local/share/kwin/effects/softgraphite-*` |
| Native KWin effects | `~/.local/lib/qt6/plugins/kwin/effects/plugins/softgraphite_*.so` (sources: `core/native/{corners,window-layers,resize-outline}`) |
| Window decoration | `~/.local/lib/qt6/plugins/org.kde.kdecoration3/liborg.leonid.softgraphite.aurorae_pair.so` |
| Helpers, patchers, sources | `~/.local/share/soft-graphite/` (= `core/`) |
| Services | `~/.config/systemd/user/` (= `systemd/`) |
| Session environment | `~/.config/environment.d/`, `~/.config/plasma-workspace/env/` (= `env/`) |

Design decisions and the reasons behind them: `docs/design.md`.
