#!/usr/bin/env python3
import os
import sys
import json
import shutil
import subprocess
from pathlib import Path

HOME = Path.home()
BASE = HOME / ".local/share/soft-graphite"
TOOLS = BASE / "build-tools/usr"
# User-local build tools exist only where packages could not be installed;
# otherwise cmake/ninja/extra-cmake-modules come from the distribution.
BIN_NINJA = BASE / "bin/ninja" if (BASE / "bin/ninja").exists() else Path(shutil.which("ninja") or "ninja")
LIB_PLUGINS = HOME / ".local/lib/qt6/plugins"
EFFECTS_DIR = LIB_PLUGINS / "kwin/effects/plugins"
APPLETS_DIR = LIB_PLUGINS / "plasma/applets"
SHADERS_DIR = HOME / ".local/share/kwin/shaders"
PLASMOIDS = HOME / ".local/share/plasma/plasmoids"

def install(src, dst):
    """Copy via a temporary file and rename. KWin and plasmashell keep the loaded
    libraries mmapped; overwriting them in place (shutil.copy2) can crash the session."""
    dst = Path(dst)
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(f".{dst.name}.new")
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)

def run(cmd, **kwargs):
    print(">>", " ".join(str(c) for c in cmd))
    res = subprocess.run(cmd, capture_output=True, text=True, **kwargs)
    if res.returncode != 0:
        print("STDOUT:", res.stdout)
        print("STDERR:", res.stderr)
        raise RuntimeError(f"Command failed: {' '.join(str(c) for c in cmd)}")
    return res

def get_kwin_version():
    try:
        out = subprocess.check_output(["kwin_wayland", "--version"], text=True)
        return out.strip()
    except Exception:
        return "unknown"

def get_plasma_version():
    # offscreen: the pacman hook runs without a display, where plasmashell
    # aborts on --version and the stamp would never match start-kwin.py.
    try:
        out = subprocess.check_output(["plasmashell", "--version"], text=True,
                                      env={**os.environ, "QT_QPA_PLATFORM": "offscreen"})
        return out.strip()
    except Exception:
        return "unknown"

def get_qt_version():
    try:
        out = subprocess.check_output(["qmake6", "-v"], text=True)
        for line in out.splitlines():
            if "Using Qt version" in line:
                return line.strip()
        return out.strip()
    except Exception:
        return "unknown"

def build_layers():
    print("[1/5] Building softgraphite_layers_v10...")
    p = BASE / "native/window-layers/build.py"
    run([sys.executable, str(p)])
    EFFECTS_DIR.mkdir(parents=True, exist_ok=True)
    install(BASE / "native/window-layers/softgraphite_layers_v10.so", EFFECTS_DIR / "softgraphite_layers_v10.so")

def build_resize_outline():
    print("[2/5] Building softgraphite_outline_resize...")
    p = BASE / "native/resize-outline/build.py"
    run([sys.executable, str(p)])
    install(BASE / "native/resize-outline/softgraphite_outline_resize.so", EFFECTS_DIR / "softgraphite_outline_resize.so")

def build_corners():
    print("[3/5] Building softgraphite_corners...")
    corners_root = BASE / "native/corners"
    source_tar = corners_root / "source.tar.gz"
    src_parent = corners_root / "source"
    src = src_parent / "rounded-corners"
    build = corners_root / "build"
    if not src.exists():
        src_parent.mkdir(parents=True, exist_ok=True)
        run(["tar", "-xzf", str(source_tar), "-C", str(src_parent)])
    build.mkdir(parents=True, exist_ok=True)
    
    cmake_cmd = [
        "cmake", "-B", str(build), "-S", str(src), "-G", "Ninja",
        "-DCMAKE_CXX_STANDARD=23",
        f"-DCMAKE_PREFIX_PATH={TOOLS}",
        f"-DCMAKE_INCLUDE_PATH={TOOLS}/include",
        f"-DCMAKE_MAKE_PROGRAM={BIN_NINJA}",
        "-DCMAKE_BUILD_TYPE=Release"
    ]
    run(cmake_cmd)
    run([str(BIN_NINJA), "-C", str(build)])
    
    so_src = build / "bin/kwin/effects/plugins/kwin4_effect_shapecorners.so"
    install(so_src, EFFECTS_DIR / "softgraphite_corners.so")
    SHADERS_DIR.mkdir(parents=True, exist_ok=True)
    for sh in (build / "src/shaders").glob("*.frag"):
        install(sh, SHADERS_DIR / sh.name)

def build_panels():
    print("[4/5] Building libGraphitePanelTools...")
    p = BASE / "native/panels/build.py"
    run([sys.executable, str(p)])
    # Each panel plasmoid imports its own copy from contents/ui/panelnative.
    for plasmoid in ("appmenu", "dock", "keyboard"):
        install(BASE / "native/panels/libGraphitePanelTools.so",
                PLASMOIDS / f"org.leonid.softgraphite.{plasmoid}/contents/ui/panelnative/libGraphitePanelTools.so")

def build_applet_facades():
    print("[5/5] Building Plasma Applet Facades (tray, appmenu, notifications)...")
    APPLETS_DIR.mkdir(parents=True, exist_ok=True)
    applets = [
        ("tray", "org.leonid.softgraphite.tray.so"),
        ("appmenu", "org.leonid.softgraphite.appmenu.so"),
        ("notifications", "org.leonid.softgraphite.notifications.so")
    ]
    for dir_name, so_name in applets:
        d = BASE / "native/applets" / dir_name
        cpp = d / "factory.cpp"
        moc = d / "factory.moc"
        meta = d / "metadata.json"
        
        # compile
        # Qt via pkg-config and every KF6 module directory, so a new KDE release that
        # pulls in another KF6 header does not break the hook-driven rebuild.
        qt = subprocess.check_output(["pkg-config", "--cflags", "--libs", "Qt6Core", "Qt6Gui", "Qt6Qml", "Qt6Quick"], text=True).split()
        kf6 = [f"-I{p}" for p in sorted(Path("/usr/include/KF6").iterdir()) if p.is_dir()]
        # moc needs the same include paths, or it cannot expand K_PLUGIN_FACTORY_WITH_JSON
        # and the plugin is built without Qt metadata (plasmashell would not load it).
        incs = [f"-I{d}", "-I/usr/include/Plasma", "-I/usr/include/PlasmaQuick", *kf6, *[f for f in qt if f.startswith("-I")]]
        run(["/usr/lib/qt6/moc", *incs, str(cpp), "-o", str(moc)])
        cmd = [
            "g++", "-O2", "-fPIC", "-shared", "-std=c++20",
            str(cpp), "-o", str(d / so_name),
            f"-I{d}", "-I/usr/include/Plasma", "-I/usr/include/PlasmaQuick", *kf6, *qt,
            "-lPlasma", "-lKF6CoreAddons"
        ]
        run(cmd)
        if b"qt_plugin_query_metadata" not in (d / so_name).read_bytes():
            raise RuntimeError(f"{so_name}: built without Qt plugin metadata; installed copy left untouched")
        install(d / so_name, APPLETS_DIR / so_name)

def reload_system(no_reload=False):
    stamp = {
        "kwin_version": get_kwin_version(),
        "plasma_version": get_plasma_version(),
        "qt_version": get_qt_version()
    }
    (BASE / "last-built-version.json").write_text(json.dumps(stamp, indent=2))
    print(f"Recorded build version stamp: {stamp}")

    if no_reload:
        print("Skipping reload as requested.")
        return

    print("Reconfiguring KWin...")
    subprocess.run(["qdbus6", "org.kde.KWin", "/KWin", "reconfigure"], capture_output=True)
    subprocess.run(["systemctl", "--user", "try-restart", "soft-graphite-appmenu.service"], capture_output=True)
    # Native KWin effects are never unloaded/reloaded live: on Wayland that crashes
    # kwin_wayland. New builds take effect at the next login.

    print("Soft Graphite components successfully built and updated!")

def build_appmenu_bridge():
    print("[6/7] Building appmenu-bridge...")
    src = BASE / "appmenu-bridge.c"
    out = BASE / "appmenu-bridge"
    tmp = BASE / ".appmenu-bridge.new"
    flags = subprocess.check_output(["pkg-config", "--cflags", "--libs", "dbus-1", "xcb"], text=True).split()
    run(["gcc", "-O2", str(src), "-o", str(tmp), *flags])
    os.replace(tmp, out)

def sync_jetbrains():
    sync_script = BASE / "sync-jetbrains-plugins.py"
    if sync_script.exists():
        print("[7/7] Synchronizing JetBrains globalmenu plugins...")
        res = subprocess.run([sys.executable, str(sync_script)], capture_output=True, text=True)
        print((res.stdout + res.stderr).strip())

def main():
    no_reload = "--no-reload" in sys.argv
    build_layers()
    build_resize_outline()
    build_corners()
    build_panels()
    build_applet_facades()
    build_appmenu_bridge()
    sync_jetbrains()
    reload_system(no_reload=no_reload)

if __name__ == "__main__":
    main()
