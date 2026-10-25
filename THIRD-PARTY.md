# Third-party work

Soft Graphite is built on other people's free software. Their licenses and author
notices are kept in the files. Thank you to all of them.

| Part in this repo | Based on | Author | License |
|---|---|---|---|
| `theme/aurorae/` window decorations, `theme/kvantum/` widget style | [WhiteSur KDE / Kvantum](https://github.com/vinceliuice/WhiteSur-kde) | Vince Liuice | GPL-3.0 |
| `theme/icons/` | [Colloid icon theme](https://github.com/vinceliuice/Colloid-icon-theme), Grey Nord variant, recolored | Vince Liuice | GPL-3.0 |
| `theme/plasma/desktoptheme/` | Breeze Plasma theme SVG elements | KDE | LGPL |
| `plasmoids/…dock` | Plasma task manager (`plasma-desktop`) | KDE | GPL-2.0-or-later |
| `plasmoids/…tray`, `…notifications`, `…appmenu`, `…clock`, `…keyboard`, `…brightness` | Plasma system tray, notifications, app menu, digital clock, keyboard layout, brightness applets | KDE | GPL-2.0-or-later / LGPL-2.0-or-later (see each `metadata.json`) |
| `core/native/corners/` | [KDE-Rounded-Corners](https://github.com/matinlotfali/KDE-Rounded-Corners) 0.7.2 + `unified-corners.patch` | Matin Lotfaliei and contributors | GPL-3.0 |
| `core/native/aurorae-pair/` | [Aurorae](https://invent.kde.org/plasma/aurorae) v6.7.5 (native v2 decoration), left button group changed | KDE | GPL-2.0-or-later, MIT, CC0 |
| `core/native/powerdevil/ddc-responsive.patch` | [PowerDevil](https://invent.kde.org/plasma/powerdevil) v6.7.5 | KDE | GPL-2.0-or-later |
| `core/native/appmenu-gtk-module/` | [appmenu-gtk-module-wayland](https://github.com/guiodic/appmenu-gtk-module-wayland) (commit 8963fc2), port of Unity GTK+ module; made resident | guiodic, Canonical | LGPL-3.0 |
| `core/native/jetbrains-globalmenu/` | [Global Menu and Decoration](https://gitlab.com/JFronny/globalmenu) 1.4.1 incl. dbusmenu4j (`WaylandPanama.java` is a fixed copy) | JFronny | GPL-3.0-or-later |
| `core/native/jetbrains-windows/` | IntelliJ Platform classes it adapts | JetBrains | Apache-2.0 |

Not included, installed from your distribution or vendor: Fira Sans font, Kvantum
engine, the applications that get patched (ChatGPT/Codex, Antigravity, Claude Desktop,
VS Code, JetBrains IDEs, Chrome) and the JetBrains plugin itself.

Wallpapers in `theme/wallpapers/` are AI-generated for this project.
