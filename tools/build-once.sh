#!/bin/bash
# Builds the native parts that core/rebuild-all.py does not rebuild after updates:
#   soft-graphite-edge (fullscreen panels helper), dock QML modules, plugin-path loader,
#   Aurorae window decoration (left buttons). Run AFTER core/ is copied to
#   ~/.local/share/soft-graphite. Everything is installed into the user's home only.
#
#   tools/build-once.sh            # build and install
#   DEST=/some/dir tools/build-once.sh   # install under another root (for testing)
#
# Requires: base-devel cmake ninja extra-cmake-modules qt6-base qt6-declarative
#           layer-shell-qt kdecoration kf6 (coreaddons, config, svg), libplasma,
#           libdbusmenu-gtk3 (GTK global menu), libxcb, dbus.
set -euo pipefail
DEST=${DEST:-$HOME}
SG=${SG:-$HOME/.local/share/soft-graphite}
PLASMOIDS=$DEST/.local/share/plasma/plasmoids
QTPLUGINS=$DEST/.local/lib/qt6/plugins
MOC=/usr/lib/qt6/moc
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Install via a temporary file + rename: running KWin/plasmashell keep loaded
# libraries mmapped, overwriting them in place can crash the session.
install_file() { mkdir -p "$(dirname "$2")"; cp "$1" "$2.new"; mv -f "$2.new" "$2"; }

echo "[1/7] soft-graphite-edge"
cp "$SG/native/edge/main.cpp" "$work/"
flags=$(pkg-config --cflags --libs Qt6Gui Qt6DBus)
$MOC $(pkg-config --cflags Qt6Gui Qt6DBus) "$work/main.cpp" -o "$work/main.moc"
g++ -std=c++20 -O2 -fPIC -I"$work" "$work/main.cpp" -o "$work/soft-graphite-edge" $flags -lLayerShellQtInterface
install_file "$work/soft-graphite-edge" "$DEST/.local/share/soft-graphite/soft-graphite-edge"
chmod +x "$DEST/.local/share/soft-graphite/soft-graphite-edge"

echo "[2/7] appmenu-bridge"
gcc -O2 "$SG/appmenu-bridge.c" -o "$work/appmenu-bridge" $(pkg-config --cflags --libs dbus-1 xcb)
install_file "$work/appmenu-bridge" "$DEST/.local/share/soft-graphite/appmenu-bridge"
chmod +x "$DEST/.local/share/soft-graphite/appmenu-bridge"

echo "[3/7] dock QML modules"
qml=$(pkg-config --cflags --libs Qt6Qml Qt6Core)
cp "$SG/native/dock-backend-loader/loader.cpp" "$work/"
$MOC $(pkg-config --cflags Qt6Qml) "$work/loader.cpp" -o "$work/loader.moc"
g++ -std=c++20 -O2 -fPIC -shared -I"$work" "$work/loader.cpp" -o "$work/libGraphiteBackendLoader.so" $qml
install_file "$work/libGraphiteBackendLoader.so" "$PLASMOIDS/org.leonid.softgraphite.dock/contents/ui/native/libGraphiteBackendLoader.so"
install_file "$SG/native/dock-backend-loader/qmldir" "$PLASMOIDS/org.leonid.softgraphite.dock/contents/ui/native/qmldir"
python3 "$SG/native/dock-launchers/build.py"
install_file "$SG/native/dock-launchers/libGraphiteLauncherSync.so" "$PLASMOIDS/org.leonid.softgraphite.dock/contents/ui/launchersync/libGraphiteLauncherSync.so"
printf 'module Graphite.LauncherSync\nplugin GraphiteLauncherSync\n' > "$work/qmldir"
install_file "$work/qmldir" "$PLASMOIDS/org.leonid.softgraphite.dock/contents/ui/launchersync/qmldir"

echo "[4/7] plugin-path loader"
cp "$SG/native-plugin-loader/native/path.cpp" "$work/"
$MOC $(pkg-config --cflags Qt6Qml) "$work/path.cpp" -o "$work/path.moc"
g++ -std=c++20 -O2 -fPIC -shared -I"$work" "$work/path.cpp" -o "$work/libGraphitePluginPath.so" $qml
install_file "$work/libGraphitePluginPath.so" "$DEST/.local/share/soft-graphite/native-plugin-loader/native/libGraphitePluginPath.so"

echo "[5/7] Aurorae decoration (org.leonid.softgraphite.aurorae_pair)"
cmake -S "$SG/native/aurorae-pair/aurorae-standalone" -B "$work/aurorae" -G Ninja -DCMAKE_BUILD_TYPE=Release ${CMAKE_EXTRA:-} >/dev/null
cmake --build "$work/aurorae" >/dev/null
so=$(find "$work/aurorae" -name 'liborg.leonid.softgraphite.aurorae_pair.so' | head -1)
[ -n "$so" ] || { echo "aurorae_pair library not found" >&2; exit 1; }
install_file "$so" "$QTPLUGINS/org.kde.kdecoration3/liborg.leonid.softgraphite.aurorae_pair.so"

echo "[6/7] ChatGPT/Codex menu exporter (used only by the ChatGPT patch)"
python3 "$SG/native/chatgpt-menu/build.py"

echo "[7/7] GTK 3 global menu module (appmenu-gtk-module-wayland)"
if pkg-config --exists dbusmenu-gtk3-0.4; then
    cmake -S "$SG/native/appmenu-gtk-module/source" -B "$work/gtkmenu" -G Ninja -DCMAKE_BUILD_TYPE=Release >/dev/null
    cmake --build "$work/gtkmenu" >/dev/null
    mods="$DEST/.local/share/soft-graphite/appmenu/lib/gtk-3.0/modules"
    install_file "$work/gtkmenu/libappmenu-gtk-module-wayland.so" "$mods/libappmenu-gtk-module-wayland.so"
    ln -sfn libappmenu-gtk-module-wayland.so "$mods/libappmenu-gtk-module.so"
else
    echo "  skipped: install libdbusmenu-gtk3 first" >&2
fi

echo "Done. Effects, applets and panel tools: python3 $SG/rebuild-all.py --no-reload"
