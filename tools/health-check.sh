#!/usr/bin/env bash
# Проверка состояния «Мягкого графита». Только чтение: ничего не меняет и не перезагружает.
set -u
SG="$HOME/.local/share/soft-graphite"
ok()   { printf '  \e[32mOK\e[0m   %s\n' "$*"; }
bad()  { printf '  \e[31mFAIL\e[0m %s\n' "$*"; FAILS=$((FAILS+1)); }
warn() { printf '  \e[33mWARN\e[0m %s\n' "$*"; }
FAILS=0

echo "== Версии (текущие vs собранные)"
kv=$(kwin_wayland --version 2>/dev/null); pv=$(plasmashell --version 2>/dev/null)
qv=$(pacman -Q qt6-base 2>/dev/null | cut -d" " -f2)
echo "  сейчас: $kv | $pv | Qt $qv"
if [[ -f "$SG/last-built-version.json" ]]; then
  bk=$(python3 -I -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("kwin_version",""),"|",d.get("plasma_version",""))' "$SG/last-built-version.json")
  echo "  собрано: $bk"
  [[ "$bk" == "$kv | $pv" ]] && ok "нативные модули собраны под текущие KWin/Plasma" || bad "версии разошлись — нужна пересборка (rebuild-all.py)"
else
  bad "нет last-built-version.json"
fi

echo "== Службы"
for u in soft-graphite-edge.service soft-graphite-appmenu.service plasma-powerdevil.service \
         codex-autopatch.path antigravity-autopatch.path claude-autopatch.path jetbrains-plugin-sync.path; do
  s=$(systemctl --user is-active "$u" 2>/dev/null)
  [[ "$s" == active ]] && ok "$u" || bad "$u: $s"
done
for u in codex-autopatch.service antigravity-autopatch.service claude-autopatch.service jetbrains-plugin-sync.service; do
  systemctl --user is-failed --quiet "$u" 2>/dev/null && bad "$u в состоянии failed (последний автопатч упал)"
done

echo "== KWin: эффекты и скрипт"
while IFS= read -r e; do
  r=$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$e" 2>/dev/null)
  [[ "$r" == true ]] && ok "эффект $e" || bad "эффект $e не загружен"
done < <(grep -oP '^\K(softgraphite[^=]*|soft-graphite[^=]*)(?=Enabled=true)' "$HOME/.config/kwinrc" | grep -v '^soft-graphite-fullscreen$')
r=$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded soft-graphite-fullscreen 2>/dev/null)
[[ "$r" == true ]] && ok "скрипт soft-graphite-fullscreen" || bad "скрипт soft-graphite-fullscreen не загружен"

echo "== Нативные плагины: зависимости"
for so in "$HOME"/.local/lib/qt6/plugins/plasma/applets/*.so \
          "$HOME"/.local/lib/qt6/plugins/kwin/effects/plugins/softgraphite_{corners,layers_v10,outline_resize}.so; do
  [[ -f "$so" ]] || { bad "нет файла $(basename "$so")"; continue; }
  miss=$(ldd "$so" 2>/dev/null | grep 'not found')
  [[ -z "$miss" ]] && ok "$(basename "$so")" || bad "$(basename "$so"): $miss"
done

echo "== pacman-хук"
if [[ -f /etc/pacman.d/hooks/99-softgraphite.hook ]]; then
  ok "99-softgraphite.hook установлен"
  cmp -s /etc/pacman.d/hooks/99-softgraphite.hook "$SG/99-softgraphite.hook" || warn "хук в /etc отличается от копии в soft-graphite (sudo cp, см. revisions/44)"
else
  bad "pacman-хук отсутствует"
fi

echo "== Глобальное меню JetBrains и Claude"
GM="$SG/plugins/globalmenu/lib"
if python3 -I - "$SG" <<'PY_CHECK'
import sys, zipfile
from pathlib import Path
sg = Path(sys.argv[1])
lib = sg / 'plugins/globalmenu/lib'
try:
    jars = [p for p in lib.glob('globalmenu-*.jar') if 'searchableOptions' not in p.name]
    assert len(jars) == 1
    with zipfile.ZipFile(jars[0]) as archive:
        assert b'dev.softgraphite.globalmenu.FrameActivationExport' in archive.read('META-INF/plugin.xml')
        archive.getinfo('dev/softgraphite/globalmenu/FrameActivationExport.class')
    jars = list(lib.glob('dbusmenu4j-*.jar'))
    assert len(jars) == 1
    entry = 'dev/jfronny/dbusmenu4j/WaylandPanama.class'
    with zipfile.ZipFile(jars[0]) as archive:
        assert archive.read(entry) == (sg / 'native/jetbrains-globalmenu/classes' / entry).read_bytes()
except (AssertionError, OSError, KeyError, zipfile.BadZipFile):
    sys.exit(1)
PY_CHECK
then
  ok "плагин globalmenu пропатчен (очередь Wayland, экспорт при активации окна)"
else
  bad "плагин globalmenu не пропатчен — python3 $SG/sync-jetbrains-plugins.py"
fi
for ide in "$HOME"/.local/share/JetBrains/*[0-9][0-9][0-9][0-9].[0-9]*/; do
  [[ -d "$ide" ]] || continue
  if [[ -L "$ide/globalmenu" ]]; then ok "$(basename "$ide"): плагин подключён"
  elif [[ -d "$ide/globalmenu" ]]; then warn "$(basename "$ide"): своя копия плагина (IDE обновила?) — патчится sync-jetbrains-plugins.py"
  else bad "$(basename "$ide"): плагин не подключён"; fi
done
[[ -x "$HOME/.local/bin/claude-desktop" ]] && ok "обёртка claude-desktop (XWayland + глобальное меню)" || bad "нет ~/.local/bin/claude-desktop"
if [[ -d /usr/lib/claude-desktop ]]; then
  python3 "$SG/rebuild-claude.py" --check && ok "Claude: пропатченная копия соответствует пакету" \
    || warn "Claude: копия устарела или отсутствует — пересоберётся при запуске/claude-autopatch"
else
  ok "Claude Desktop не установлен — проверка копии не требуется"
fi

echo "== Патчи приложений (пакет vs пропатченная копия)"
for p in chatgpt-desktop-bin antigravity; do
  v=$(pacman -Q "$p" 2>/dev/null) && echo "  пакет: $v" || warn "пакет $p не найден"
done
python3 -I - "$SG" <<'PY'
import json, os, sys
sg = sys.argv[1]
for name, js, root, key in [("ChatGPT/Codex", "codex-frame-version.json", "/usr/lib/chatgpt", None),
                            ("Antigravity", "antigravity-version.json", "/opt/Antigravity", "source")]:
    try:
        d = json.load(open(os.path.join(sg, js)))
        d = d[key] if key else d
        stale = [f for f, (size, mtime) in d.items()
                 if [os.stat(os.path.join(root, f)).st_size, os.stat(os.path.join(root, f)).st_mtime_ns] != [size, mtime]]
        print(f"  \033[33mWARN\033[0m {name}: пакет обновился, пропатченная копия устарела ({', '.join(stale)}) — пересоберётся при запуске/autopatch"
              if stale else f"  \033[32mOK\033[0m   {name}: пропатченная копия соответствует установленной версии")
    except Exception as e:
        print(f"  \033[33mWARN\033[0m {name}: не удалось сверить ({e})")
PY

echo "== Ошибки Plasma/KWin с текущей загрузки (по Soft Graphite)"
errs=$(journalctl --user -b --no-pager -o cat 2>/dev/null \
  | grep -iE 'softgraphite|soft-graphite|org\.leonid' \
  | grep -iE 'error|fail|not a type|cannot|undefined|segfault' | sort | uniq -c | sort -rn | head -15)
[[ -z "$errs" ]] && ok "ошибок не найдено" || { warn "есть сообщения (первые 15):"; echo "$errs" | sed 's/^/      /'; }

echo "== Синхронизация календаря Google (rev 74)"
python3 -B "$(dirname -- "${BASH_SOURCE[0]}")/calendar-sync-health.py" \
  || bad "календарная синхронизация требует внимания (см. выше)"

echo
[[ $FAILS -eq 0 ]] && echo "Итог: всё в порядке" || echo "Итог: проблем — $FAILS"

[[ $FAILS -eq 0 ]]
