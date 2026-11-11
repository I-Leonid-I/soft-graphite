#!/usr/bin/python3
"""Read-only checks for calendar sync after package upgrades. No repair/restarts."""
import json
import os
from pathlib import Path
import subprocess
import sys

SG = Path.home() / ".local/share/soft-graphite"
BASE = SG / "native/google-tasks"
failures = []


def check(label, function):
    try:
        function()
        print("  OK  ", label)
    except Exception as error:
        failures.append(label)
        print("  FAIL", label, "—", error)


def run(*command):
    return subprocess.check_output(command, text=True, stderr=subprocess.STDOUT, timeout=10).strip()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def dependencies():
    require(Path("/usr/bin/akonadiserver").is_file(), "Akonadi не установлен")
    run("qdbus6", "--version")


def service():
    result = subprocess.run(("systemctl", "--user", "is-active", "soft-graphite-google-sync.service"),
                            capture_output=True, text=True, timeout=10)
    require(result.returncode != 0, "старый секундный опрос всё ещё запущен")
    import sqlite3
    with sqlite3.connect(f"file:{Path.home()}/.local/share/akonadi/akonadi.db?mode=ro", uri=True) as db:
        rows = db.execute("""SELECT DISTINCT c.id,c.cachePolicyInherit,c.cachePolicyCheckInterval
            FROM CollectionTable c JOIN ResourceTable r ON r.id=c.resourceId
            JOIN CollectionMimeTypeRelation cm ON cm.Collection_id=c.id
            JOIN MimeTypeTable m ON m.id=cm.MimeType_id
            WHERE r.name='akonadi_google_resource_0' AND c.enabled=1
            AND m.name IN ('application/x-vnd.akonadi.calendar.event','application/x-vnd.akonadi.calendar.todo')""").fetchall()
    require(bool(rows) and all(not inherit and interval == 5 for _,inherit,interval in rows),
            "штатный интервал календарей/задач отличается от 5 минут")


def libraries():
    versions = run("pacman", "-Q", "libkgapi", "qt6-base", "kcalendarcore", "kwallet")
    stamp = json.loads((BASE / "built.json").read_text())
    require(stamp["packages"].strip() == versions, "приватные библиотеки требуют пересборки при следующем запуске ресурса")
    require(stamp.get("patchLevel") == 7402, "нет защиты квоты/дескрипторов rev 74")
    for name in ("Core", "Tasks", "Calendar"):
        path = BASE / "lib" / f"libKPim6GAPI{name}.so.6"
        require(path.is_file(), f"отсутствует {path.name}")
        require("not found" not in run("ldd", str(path)), f"не найдены зависимости {path.name}")


def resource():
    service = "org.freedesktop.Akonadi.Resource.akonadi_google_resource_0"
    api = run("qdbus6", service, "/")
    for method in ("Resource.synchronize()", "Resource.taskList()", "Status.isOnline()", "Resource.synchronized()"):
        require(method in api, f"изменился D-Bus API: {method}")
    pid = run("qdbus6", "org.freedesktop.DBus", "/org/freedesktop/DBus",
              "org.freedesktop.DBus.GetConnectionUnixProcessID", service)
    maps = Path(f"/proc/{int(pid)}/maps").read_text()
    for name in ("Core", "Tasks", "Calendar"):
        path = str(BASE / "lib" / f"libKPim6GAPI{name}.so.6")
        require(path in maps, f"ресурс использует системную {name}: проверить журнал launch.py")
        require(not any(path in line and "(deleted)" in line for line in maps.splitlines()),
                f"{name} пересобрана, но ресурс ещё использует прежний файл")


def qml():
    path = Path("/usr/lib/qt6/qml/org/kde/plasma/workspace/dbus/dbusplugin.qmltypes")
    require("/SignalWatcher " in path.read_text(), "API SignalWatcher отсутствует в новой Plasma")
    view = Path.home() / ".local/share/plasma/plasmoids/org.leonid.softgraphite.clock/contents/ui/CalendarView.qml"
    require("function dbusstatus(" in view.read_text(), "нет обновления открытого виджета")


def heartbeat():
    service = "org.freedesktop.Akonadi.Resource.akonadi_google_resource_0"
    pid = int(run("qdbus6", "org.freedesktop.DBus", "/org/freedesktop/DBus",
                  "org.freedesktop.DBus.GetConnectionUnixProcessID", service))
    count = len(list(Path(f"/proc/{pid}/fd").iterdir()))
    require(count < 256, f"подозрительно много открытых файлов: {count}")
    path = Path.home() / ".local/state/soft-graphite/google-api-budget.json"
    require(isinstance(json.loads(path.read_text()), list), "счётчик запросов недоступен/повреждён")


if __name__ == "__main__":
    for label, function in (("инструменты Akonadi", dependencies), ("штатная синхронизация раз в 5 минут без помощника", service),
                            ("версии и зависимости патчей Google", libraries),
                            ("D-Bus и реально загруженные библиотеки", resource),
                            ("обновление открытого календаря", qml),
                            ("дескрипторы и постоянный счётчик квоты", heartbeat)):
        check(label, function)
    sys.exit(bool(failures))
