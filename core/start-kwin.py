import subprocess,json,sys
from pathlib import Path
name='soft-graphite-fullscreen'
base=Path.home()/'.local/share/soft-graphite'
source=Path.home()/'.local/share/kwin/scripts'/name/'contents/code/main.js'
try: state=json.loads((base/'session-state.json').read_text())
except (OSError,ValueError): state={}
p=base/'fullscreen-runtime.js'
p.write_text(source.read_text().replace('const initialState={};','const initialState='+json.dumps(state,ensure_ascii=False)+';'))
subprocess.run(['qdbus6','org.kde.KWin','/Scripting','unloadScript',name],stdout=subprocess.DEVNULL)
subprocess.run(['qdbus6','org.kde.KWin','/Scripting','loadScript',str(p),name],check=True,stdout=subprocess.DEVNULL)
subprocess.run(['qdbus6','org.kde.KWin','/Scripting','start'],check=True)

# Make user-installed native effects available even when KWin started before
# the login environment gained QT_PLUGIN_PATH. Runs once at service startup.
import configparser
cfg=configparser.ConfigParser(interpolation=None);cfg.read(Path.home()/'.config/kwinrc')
# If a future update makes the custom decoration unavailable, restore standard
# buttons in the fallback decoration instead of leaving an empty button layout.
expected='org.leonid.softgraphite.aurorae'
if cfg.get('org.kde.kdecoration2','library',fallback='')==expected:
    info=subprocess.run(['qdbus6','org.kde.KWin','/KWin','supportInformation'],capture_output=True,text=True).stdout
    if 'Decoration\n' in info and 'Plugin: '+expected not in info:
        subprocess.run(['kwriteconfig6','--file','kwinrc','--group','org.kde.kdecoration2','--key','ButtonsOnRight','--notify','IAX'],check=True)
        subprocess.run(['qdbus6','org.kde.KWin','/KWin','reconfigure'],check=True)
        subprocess.run(['gsettings','set','org.gnome.desktop.wm.preferences','button-layout','menu:minimize,maximize,close'])
        print('Soft Graphite: decoration fallback active; standard buttons restored.',flush=True)

# Check if KWin, Plasma, or Qt version changed since last build
stamp_file=base/'last-built-version.json'
try:
    kw_ver=subprocess.check_output(['kwin_wayland','--version'],text=True).strip()
    ps_ver=subprocess.check_output(['plasmashell','--version'],text=True).strip()
    try:
        qt_out=subprocess.check_output(['qmake6','-v'],text=True)
        qt_ver=next((l.strip() for l in qt_out.splitlines() if "Using Qt version" in l), qt_out.strip())
    except Exception:
        qt_ver='unknown'
    rebuild=False
    if not stamp_file.exists():
        rebuild=True
    else:
        try:
            stamp=json.loads(stamp_file.read_text())
            if stamp.get('kwin_version')!=kw_ver or stamp.get('plasma_version')!=ps_ver or (stamp.get('qt_version') and stamp.get('qt_version')!=qt_ver):
                rebuild=True
        except Exception:
            rebuild=True
    if rebuild:
        print('Soft Graphite: system update detected, rebuilding native modules...',flush=True)
        try:
            subprocess.run([sys.executable,str(base/'rebuild-all.py'),'--no-reload'],check=True)
        except Exception as e:
            print('Soft Graphite: auto-rebuild failed:',e,flush=True)
except Exception:
    pass

try:
    if (base / 'sync-jetbrains-plugins.py').exists():
        subprocess.run([sys.executable, str(base / 'sync-jetbrains-plugins.py')], capture_output=True)
except Exception:
    pass

effects=('softgraphite_corners','softgraphite_outline_resize','softgraphite_layers_v10')
pending=[]
for effect in effects:
    loaded=subprocess.run(['qdbus6','org.kde.KWin','/Effects','isEffectLoaded',effect],capture_output=True,text=True)
    if loaded.stdout.strip()!='true' and cfg.getboolean('Plugins',effect+'Enabled',fallback=False):
        pending.append(effect)
if pending:
    loader='graphite-user-plugin-path'
    subprocess.run(['qdbus6','org.kde.KWin','/Scripting','loadDeclarativeScript',str(base/'native-plugin-loader/Loader.qml'),loader],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['qdbus6','org.kde.KWin','/Scripting','start'],check=True)
    import time
    time.sleep(.15)
    for effect in pending:
        result=subprocess.run(['qdbus6','org.kde.KWin','/Effects','loadEffect',effect],capture_output=True,text=True)
        if result.stdout.strip()!='true':print('Soft Graphite: effect '+effect+' could not be loaded; desktop controls remain available.',flush=True)
    subprocess.run(['qdbus6','org.kde.KWin','/Scripting','unloadScript',loader],stdout=subprocess.DEVNULL)
