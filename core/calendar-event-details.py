#!/usr/bin/env python3
"""Details of one calendar event for the Soft Graphite clock popup (rev 51).

The Plasma calendar plugin only exposes title, time, description and colour,
so on click the clock runs this helper once. It reads the Akonadi SQLite
database read-only and prints JSON: location, description, organizer,
attendees, links, calendar name and a Google Calendar link.

Usage: calendar-event-details.py TITLE START_MS END_MS
       calendar-event-details.py --tasks   (Google Tasks with a due date, as JSON)
"""
import base64
import json
import os
import re
import sqlite3
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

AKONADI = os.path.expanduser("~/.local/share/akonadi")
DB = os.path.join(AKONADI, "akonadi.db")
LOCAL = datetime.now().astimezone().tzinfo
URL_RE = re.compile(r"https?://[^\s<>\"')\]]+")


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text)


def unescape(value):
    return (value.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
            .replace("\\;", ";").replace("\\\\", "\\"))


def parse_line(line):
    head, _, value = line.partition(":")
    # parameter values may be quoted and contain ':' — split head carefully
    parts = re.findall(r'(?:[^;"]|"[^"]*")+', head)
    name = parts[0].upper() if parts else ""
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return name, params, value


def first_vevent(ical):
    lines = unfold(ical).splitlines()
    props, inside, depth = [], False, 0
    for line in lines:
        if line == "BEGIN:VEVENT":
            inside = True
            continue
        if not inside:
            continue
        if line.startswith("BEGIN:"):
            depth += 1
        elif line.startswith("END:"):
            if depth == 0:
                break
            depth -= 1
        elif depth == 0:
            props.append(parse_line(line))
    return props


def parse_dt(value, params):
    if params.get("VALUE") == "DATE" or re.fullmatch(r"\d{8}", value):
        d = datetime.strptime(value[:8], "%Y%m%d")
        return d.replace(tzinfo=LOCAL), True
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc), False
    dt = datetime.strptime(value[:15], "%Y%m%dT%H%M%S")
    tz = params.get("TZID")
    try:
        return dt.replace(tzinfo=ZoneInfo(tz) if tz else LOCAL), False
    except Exception:
        return dt.replace(tzinfo=LOCAL), False


def person(params, value):
    email = re.sub(r"(?i)^mailto:", "", value)
    return {
        "name": params.get("CN", ""),
        "email": email,
        "status": params.get("PARTSTAT", ""),
        "optional": params.get("ROLE", "") == "OPT-PARTICIPANT",
    }


def load_payload(cur, item_id):
    row = cur.execute(
        "select data, storage from parttable p join parttypetable t on t.id = p.partTypeId "
        "where p.pimItemId = ? and t.name = 'RFC822'", (item_id,)).fetchone()
    if not row:
        return None
    data, storage = row
    if isinstance(data, bytes):
        data = data.decode("utf-8", "replace")
    if storage == 1:  # stored in an external file
        name = data.strip()
        for root in (os.path.join(AKONADI, "file_db_data"),):
            path = os.path.join(root, name)
            if not os.path.exists(path):
                sub = name.split("_")[0]
                path = os.path.join(root, str(int(sub) % 100), name)
            if os.path.exists(path):
                with open(path, encoding="utf-8", errors="replace") as f:
                    return f.read()
        return None
    return data


def collection_info(cur, collection_id):
    name, remote = "", ""
    row = cur.execute("select remoteId from collectiontable where id = ?", (collection_id,)).fetchone()
    if row:
        remote = row[0] or ""
    row = cur.execute(
        "select value from collectionattributetable where collectionId = ? and cast(type as text) = 'ENTITYDISPLAY'",
        (collection_id,)).fetchone()
    if row:
        value = row[0].decode("utf-8", "replace") if isinstance(row[0], bytes) else row[0]
        m = re.match(r'\("((?:[^"\\]|\\.)*)"', value or "")
        if m:
            name = m.group(1)
    return name or remote, remote


def first_vtodo(ical):
    return first_vevent(ical.replace("BEGIN:VTODO", "BEGIN:VEVENT"))


def tasks():
    """All tasks with a due date; the clock places them on days itself."""
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=2)
    cur = con.cursor()
    out = []
    for item_id, collection_id in cur.execute(
            "select p.pimItemId, i.collectionId from parttable p "
            "join parttypetable t on t.id = p.partTypeId join pimitemtable i on i.id = p.pimItemId "
            "where t.name = 'RFC822' and (p.storage = 1 or p.data like '%BEGIN:VTODO%')").fetchall():
        ical = load_payload(con.cursor(), item_id)
        if not ical or "BEGIN:VTODO" not in ical:
            continue
        props = first_vtodo(ical)
        get = lambda name: next((unescape(v) for n, _, v in props if n == name), "")
        due = next(((v, p) for n, p, v in props if n == "DUE"), None)
        if not due:
            continue  # Google Calendar shows only tasks with a date
        due_dt, _ = parse_dt(*due)
        status = get("STATUS")
        completed_at = next(((v, p) for n, p, v in props if n == "COMPLETED"), None)
        done_date = ""
        if completed_at:
            done_dt, _ = parse_dt(*completed_at)
            done_date = done_dt.astimezone().date().isoformat()
        calendar, _ = collection_info(cur, collection_id)
        out.append({
            "id": item_id,
            "title": get("SUMMARY"),
            "notes": get("DESCRIPTION"),
            "due": due_dt.astimezone(LOCAL).date().isoformat() if due_dt.tzinfo else due_dt.date().isoformat(),
            "completed": status == "COMPLETED" or get("PERCENT-COMPLETE") == "100",
            "completedOn": done_date,
            "list": calendar,
        })
    out.sort(key=lambda t: (t["due"], t["title"]))
    print(json.dumps(out, ensure_ascii=False))


def main():
    if sys.argv[1:2] == ["--tasks"]:
        tasks()
        return
    title, start_ms, end_ms = sys.argv[1], int(float(sys.argv[2])), int(float(sys.argv[3]))
    start = datetime.fromtimestamp(start_ms / 1000, timezone.utc)
    duration = (end_ms - start_ms) / 1000

    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True, timeout=2)
    cur = con.cursor()
    like = "%SUMMARY%" + title.replace("%", "").split("\n")[0][:40] + "%"
    best, best_score = None, -1
    for item_id, collection_id in cur.execute(
            "select p.pimItemId, i.collectionId from parttable p "
            "join parttypetable t on t.id = p.partTypeId join pimitemtable i on i.id = p.pimItemId "
            "where t.name = 'RFC822' and (p.storage = 1 or p.data like ?)", (like,)).fetchall():
        ical = load_payload(con.cursor(), item_id)
        if not ical or "BEGIN:VEVENT" not in ical:
            continue
        props = first_vevent(ical)
        summary = next((unescape(v) for n, _, v in props if n == "SUMMARY"), "")
        if summary.strip() != title.strip():
            continue
        dtstart = next(((v, p) for n, p, v in props if n == "DTSTART"), None)
        if not dtstart:
            continue
        ev_start, all_day = parse_dt(*dtstart)
        recurrence_id = next(((v, p) for n, p, v in props if n == "RECURRENCE-ID"), None)
        has_rrule = any(n == "RRULE" for n, _, _ in props)
        score = 0
        if abs((ev_start - start).total_seconds()) < 60 or (all_day and ev_start.date() == start.astimezone().date()):
            score = 3
        elif recurrence_id:
            rid, _ = parse_dt(*recurrence_id)
            score = 3 if rid.astimezone().date() == start.astimezone().date() else 0
        elif has_rrule and ev_start <= start + timedelta(minutes=1):
            local_ev, local_start = ev_start.astimezone(), start.astimezone()
            score = 2 if (local_ev.hour, local_ev.minute) == (local_start.hour, local_start.minute) else 1
        if score > best_score:
            best, best_score = (props, collection_id), score
    if not best:
        print(json.dumps({"found": False}))
        return

    props, collection_id = best
    get = lambda name: next((unescape(v) for n, _, v in props if n == name), "")
    description, location = get("DESCRIPTION"), get("LOCATION")
    attendees = [person(p, v) for n, p, v in props if n == "ATTENDEE"]
    organizer = next((person(p, v) for n, p, v in props if n == "ORGANIZER"), None)
    calendar, remote = collection_info(cur, collection_id)
    event_id = get("X-KDE-LIBKGAPI-EVENTID")
    google_url = ""
    if event_id and remote:
        eid = base64.urlsafe_b64encode(f"{event_id} {remote}".encode()).decode().rstrip("=")
        google_url = f"https://www.google.com/calendar/event?eid={eid}"
    links = []
    for text in (get("X-KDE-LIBKGAPI-EVENTHANGOUTLINK"), location, description, get("URL")):
        for url in URL_RE.findall(text):
            if url not in links:
                links.append(url)
    print(json.dumps({
        "found": True,
        "title": get("SUMMARY"),
        "location": location,
        "description": description,
        "organizer": organizer,
        "attendees": attendees,
        "links": links,
        "calendar": calendar,
        "googleUrl": google_url,
        "recurring": any(n == "RRULE" for n, _, _ in props),
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as ex:  # the popup shows what it already has
        print(json.dumps({"found": False, "error": repr(ex)}))
