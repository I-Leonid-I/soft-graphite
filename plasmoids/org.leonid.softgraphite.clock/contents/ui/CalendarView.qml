/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2015 Martin Klapetek <mklapetek@kde.org>
    SPDX-FileCopyrightText: 2021 Carl Schwan <carlschwan@kde.org>
    SPDX-FileCopyrightText: 2023 ivan tkachenko <me@ratijas.tk>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.workspace.calendar as PlasmaCalendar
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.private.digitalclock
import org.kde.kirigami as Kirigami
import org.kde.plasma.clock
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.workspace.dbus as DBus

// Soft Graphite calendar, variant "day by hours" (rev 51):
// - leading column: big date, all-day events, the selected day on an hour
//   timeline with a "now" line, world clocks when several time zones are set;
// - trailing column: month grid with one coloured dot per event calendar.
// Events come from the enabled calendar plugins (pimevents = Akonadi/Google).
PlasmaExtras.Representation {
    id: calendar

    readonly property var appletInterface: root

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    Layout.minimumWidth: Kirigami.Units.gridUnit * 38
    Layout.maximumWidth: Kirigami.Units.gridUnit * 80
    Layout.minimumHeight: Kirigami.Units.gridUnit * 24
    Layout.maximumHeight: Kirigami.Units.gridUnit * 40

    collapseMarginsHint: true

    readonly property int paddings: Kirigami.Units.largeSpacing
    readonly property var clockZones: root.selectedTimeZonesDeduplicatingExplicitLocalTimeZone()
    readonly property bool showClocks: clockZones.length > 1
    // Holiday sublabels are gone (holidays come from Google); kept for Tooltip.qml.
    readonly property string todayAuxilliaryText: ""

    readonly property color accentColor: Kirigami.Theme.focusColor
    readonly property color lineColor: Qt.alpha(Kirigami.Theme.textColor, 0.08)
    readonly property real hourHeight: Kirigami.Units.gridUnit * 2

    // Not bound to the ticking clock: a minute tick must not re-scroll the day.
    property date currentDate: new Date()
    property var dayEvents: ({ allDay: [], timed: [], count: 0 })

    // Event card (rev 51): the clicked event and what the helper read from Akonadi.
    property var selectedEvent: null
    // Stays set while the card fades out, so its content does not vanish first.
    property var shownEvent: null
    property real cardShown: selectedEvent ? 1 : 0
    Behavior on cardShown { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    property var eventDetails: null
    property string detailsCommand: ""
    property var cardDays: []

    function dayTitle(d: date): string {
        const today = root.currentTime;
        const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
        if (calendar.sameDay(d, today)) return "Сегодня";
        if (calendar.sameDay(d, tomorrow)) return "Завтра";
        return Qt.locale().toString(d, "dddd, d MMMM");
    }

    function buildCardDays() {
        const days = [];
        const base = calendar.currentDate;
        for (let i = 0; i < 8 && days.length < 2; ++i) {
            const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() + i);
            const { allDay, timed } = calendar.collectEvents(d);
            const events = calendar.tasksForDay(d).concat(allDay, timed);
            if (i === 0 || events.length) {
                days.push({ title: calendar.dayTitle(d), events: events });
            }
        }
        calendar.cardDays = days;
    }

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate();
    }

    // QDate from the model is midnight UTC, MonthView-style dates are local.
    function sameUtcDay(utc: date, local: date): bool {
        return utc.getUTCFullYear() === local.getFullYear()
            && utc.getUTCMonth() === local.getMonth()
            && utc.getUTCDate() === local.getDate();
    }

    // Google colours are vivid; pull them slightly towards the text colour so
    // they sit calmly on graphite (and on the light variant).
    function softColor(c): color {
        return c ? Kirigami.ColorUtils.linearInterpolation(c, Kirigami.Theme.textColor, 0.18)
                 : Kirigami.Theme.highlightColor;
    }

    // Google Tasks (rev 51): read by the helper when the popup opens. Like in
    // Google Calendar, a task sits on its due date; an unfinished overdue task
    // moves to today until it is done.
    readonly property string tasksCommand: 'python3 "$HOME/.local/share/soft-graphite/calendar-event-details.py" --tasks'
    readonly property color taskColor: Kirigami.Theme.focusColor
    property var allTasks: []
    // Where a task was when it was ticked in this popup session, so it does
    // not jump to another day right after the click.
    property var taskPlacement: ({})
    property string taskDoneCommand: ""
    property var taskDoneRevert: null

    function setTaskDone(task, done: bool) {
        const shownToday = (calendar.dayEvents.tasks ?? []).some(t => t.id === task.id);
        const placement = Object.assign({}, calendar.taskPlacement);
        placement[task.id] = shownToday ? calendar.isoDate(calendar.currentDate) : task.due;
        calendar.taskPlacement = placement;
        const before = calendar.allTasks;
        calendar.taskDoneRevert = before;
        const today = calendar.isoDate(root.currentTime);
        calendar.allTasks = before.map(t => t.id === task.id
            ? Object.assign({}, t, { completed: done, completedOn: done ? today : "" }) : t);
        if (calendar.shownEvent && calendar.shownEvent.isTask && calendar.shownEvent.id === task.id) {
            const updated = Object.assign({}, calendar.shownEvent,
                { completed: done, completedOn: done ? today : "", overdue: !done && task.due < today });
            calendar.shownEvent = updated;
            if (calendar.selectedEvent) {
                calendar.selectedEvent = updated;
            }
        }
        if (calendar.selectedEvent) {
            calendar.buildCardDays();
        }
        calendar.taskDoneCommand = '"$HOME/.local/share/soft-graphite/bin/sg-task-done" ' + task.id + (done ? " 1" : " 0");
        detailsSource.connectSource(calendar.taskDoneCommand);
    }

    function isoDate(d: date): string {
        return Qt.formatDate(d, "yyyy-MM-dd");
    }

    function tasksForDay(d: date): var {
        const key = calendar.isoDate(d);
        const today = calendar.isoDate(root.currentTime);
        return calendar.allTasks
            .filter(t => {
                if (calendar.taskPlacement[t.id] !== undefined) {
                    return calendar.taskPlacement[t.id] === key;
                }
                return (!t.completed && t.due < today) ? key === today : t.due === key;
            })
            .map(t => {
                const [y, m, day] = t.due.split("-").map(Number);
                const due = new Date(y, m - 1, day);
                return Object.assign({}, t, {
                    isTask: true, allDay: true, color: String(calendar.taskColor),
                    overdue: !t.completed && t.due < today, description: t.notes,
                    startMs: due.getTime(), endMs: due.getTime() + 86400000,
                });
            })
            .sort((a, b) => (a.completed - b.completed) || (b.overdue - a.overdue) || a.due.localeCompare(b.due));
    }

    function tasksWord(n: int): string {
        const m10 = n % 10, m100 = n % 100;
        if (m10 === 1 && m100 !== 11) return "задача";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "задачи";
        return "задач";
    }

    // One dot per calendar (colour) for the given day, tasks included.
    function dayColors(d: date): var {
        const list = backend.daysModel.eventsForDate(d);
        const colors = [];
        if (calendar.tasksForDay(d).length) {
            colors.push(String(calendar.taskColor));
        }
        for (let i = 0; i < list.length && colors.length < 3; ++i) {
            const c = String(list[i].eventColor);
            if (!colors.includes(c)) {
                colors.push(c);
            }
        }
        return colors;
    }

    function capitalize(s: string): string {
        return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : s;
    }

    function eventsWord(n: int): string {
        const m10 = n % 10, m100 = n % 100;
        if (m10 === 1 && m100 !== 11) return "событие";
        if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return "события";
        return "событий";
    }

    function timeText(d: date): string {
        return Qt.formatTime(d, Qt.locale().timeFormat(Locale.ShortFormat));
    }

    function shellQuote(s: string): string {
        return "'" + String(s).replace(/'/g, "'\\''") + "'";
    }

    // Location, attendees etc. are not in the Plasma event data; the helper
    // reads them from the Akonadi database once per click.
    // The card appears once the details are read (≈0.1 s), so it animates in
    // one piece instead of growing when attendees arrive; showCardTimer is
    // the fallback if the helper is slow.
    property var pendingEvent: null
    property var pendingDetails: null

    function openEvent(ev) {
        calendar.pendingEvent = ev;
        calendar.pendingDetails = null;
        if (ev.isTask) {
            calendar.pendingDetails = { found: true, isTask: true, title: ev.title, description: ev.notes,
                                        calendar: ev.list, attendees: [], links: [] };
            calendar.showPendingEvent();
            return;
        }
        showCardTimer.restart();
        if (calendar.detailsCommand !== "") {
            detailsSource.disconnectSource(calendar.detailsCommand);
        }
        calendar.detailsCommand = 'python3 "$HOME/.local/share/soft-graphite/calendar-event-details.py" '
            + calendar.shellQuote(ev.title) + " " + ev.startMs + " " + ev.endMs;
        detailsSource.connectSource(calendar.detailsCommand);
    }

    // Calm fades (rev 51): content dissolves and reappears in place, without
    // movement. Only opening and closing the card keep the small rise.
    component Fade: SequentialAnimation {
        id: fade
        property QtObject target
        property string property
        property var pending: null
        function run(action) {
            if (running) {
                stop();
                const previous = fade.pending;
                fade.pending = null;
                if (previous) previous();
            }
            fade.pending = action;
            start();
        }
        NumberAnimation { target: fade.target; property: fade.property; to: 0; duration: 110; easing.type: Easing.InQuad }
        ScriptAction {
            script: {
                const action = fade.pending;
                fade.pending = null;
                if (action) action();
            }
        }
        NumberAnimation { target: fade.target; property: fade.property; to: 1; duration: 170; easing.type: Easing.OutQuad }
    }

    property real dayFade: 1
    property real monthFade: 1
    property real cardFade: 1
    Fade { id: dayFadeAnim; target: calendar; property: "dayFade" }
    Fade { id: monthFadeAnim; target: calendar; property: "monthFade" }
    Fade { id: cardFadeAnim; target: calendar; property: "cardFade" }

    function changeMonth(step: int) {
        monthFadeAnim.run(() => step > 0 ? backend.nextMonth() : backend.previousMonth());
    }

    function showPendingEvent() {
        showCardTimer.stop();
        const ev = calendar.pendingEvent;
        if (!ev) {
            return;
        }
        calendar.pendingEvent = null;
        const details = calendar.pendingDetails;
        const apply = () => {
            calendar.eventDetails = details;
            calendar.shownEvent = ev;
            calendar.selectedEvent = ev;
        };
        if (calendar.selectedEvent) {
            cardFadeAnim.run(apply);    // switching events: dissolve in place
        } else {
            calendar.buildCardDays();
            apply();                    // opening: the layer fades and rises
        }
    }

    function closeEvent() {
        calendar.pendingEvent = null;
        showCardTimer.stop();
        calendar.selectedEvent = null;
    }

    Timer {
        id: showCardTimer
        interval: 400
        onTriggered: calendar.showPendingEvent()
    }

    function attendeeStatus(status: string): string {
        switch (status) {
        case "ACCEPTED": return "идёт";
        case "DECLINED": return "не идёт";
        case "TENTATIVE": return "возможно";
        case "DELEGATED": return "передал";
        default: return "нет ответа";
        }
    }

    function resetToToday() {
        calendar.closeEvent();
        calendar.currentDate = root.currentTime;
        backend.displayedDate = root.currentTime;
    }

    function selectDate(d: date) {
        calendar.closeEvent();
        const otherMonth = d.getMonth() !== backend.displayedDate.getMonth() || d.getFullYear() !== backend.displayedDate.getFullYear();
        if (!calendar.sameDay(d, calendar.currentDate)) {
            dayFadeAnim.run(() => { calendar.currentDate = d; });
        }
        if (otherMonth) {
            monthFadeAnim.run(() => { backend.displayedDate = d; });
        }
    }

    // Events of one day, split into all-day and timed (hours relative to the day).
    function collectEvents(d: date): var {
        const list = backend.daysModel.eventsForDate(d);
        const dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        const allDay = [], timed = [];
        // The model can receive the same plugin data twice; show each event once.
        const seen = new Set();
        for (let i = 0; i < list.length; ++i) {
            const ev = list[i];
            const key = `${ev.title}|${ev.startDateTime.getTime()}|${ev.endDateTime.getTime()}|${ev.eventColor}`;
            if (seen.has(key)) {
                continue;
            }
            seen.add(key);
            const s = (ev.startDateTime - dayStart) / 3600000;
            const e = (ev.endDateTime - dayStart) / 3600000;
            const midnightToMidnight = ev.startDateTime.getHours() === 0 && ev.startDateTime.getMinutes() === 0
                && ev.endDateTime.getHours() === 0 && ev.endDateTime.getMinutes() === 0;
            if (ev.isAllDay || (s <= 0 && e >= 24) || midnightToMidnight) {
                allDay.push({ title: ev.title, color: ev.eventColor, description: ev.description, allDay: true,
                              startMs: ev.startDateTime.getTime(), endMs: ev.endDateTime.getTime() });
                continue;
            }
            const start = Math.max(0, s), end = Math.min(24, Math.max(e, start + 0.25));
            timed.push({
                title: ev.title, color: ev.eventColor, description: ev.description, allDay: false,
                startMs: ev.startDateTime.getTime(), endMs: ev.endDateTime.getTime(),
                start: start, end: end, visualEnd: Math.max(end, start + 0.75),
                startText: calendar.timeText(ev.startDateTime), endText: calendar.timeText(ev.endDateTime),
                lane: 0, lanes: 1,
            });
        }
        timed.sort((a, b) => a.start - b.start || b.end - a.end);
        return { allDay: allDay, timed: timed };
    }

    // Splits the selected day's events into all-day chips and timeline blocks;
    // overlapping timed events share the width in lanes.
    function updateDayEvents() {
        const { allDay, timed } = calendar.collectEvents(calendar.currentDate);
        let cluster = [], laneEnds = [], clusterEnd = -1;
        const finish = () => { for (const t of cluster) t.lanes = laneEnds.length; };
        for (const t of timed) {
            if (cluster.length && t.start >= clusterEnd) {
                finish();
                cluster = []; laneEnds = []; clusterEnd = -1;
            }
            let lane = laneEnds.findIndex(end => end <= t.start);
            if (lane < 0) {
                lane = laneEnds.length;
                laneEnds.push(t.visualEnd);
            } else {
                laneEnds[lane] = t.visualEnd;
            }
            t.lane = lane;
            cluster.push(t);
            clusterEnd = Math.max(clusterEnd, t.visualEnd);
        }
        finish();
        const tasks = calendar.tasksForDay(calendar.currentDate);
        calendar.dayEvents = { allDay: allDay, timed: timed, tasks: tasks, count: allDay.length + timed.length };
        if (timeline) {
            timeline.scrollToInteresting();
        }
    }

    onCurrentDateChanged: updateDayEvents()
    onAllTasksChanged: updateDayEvents()
    onSelectedEventChanged: Qt.callLater(() => timeline.scrollToInteresting())

    Connections {
        target: root

        function onExpandedChanged() {
            calendar.resetToToday();
            calendar.taskPlacement = {};
            if (root.expanded) {
                detailsSource.connectSource(calendar.tasksCommand);
            }
        }
    }

    // Refresh an open popup after the real Akonadi sync, without UI polling.
    // A closed popup loads tasks on opening as before.
    DBus.SignalWatcher {
        id: completedSync
        enabled: root.expanded
        busType: DBus.BusType.Session
        service: "org.freedesktop.Akonadi.Resource.akonadi_google_resource_0"
        path: "/"
        iface: "org.freedesktop.Akonadi.Resource"
        function dbussynchronized() {
            detailsSource.connectSource(calendar.tasksCommand);
            if (calendar.selectedEvent && calendar.detailsCommand) {
                detailsSource.connectSource(calendar.detailsCommand);
            }
        }
    }

    // Native per-collection refreshes report completion through status.
    DBus.SignalWatcher {
        enabled: root.expanded
        busType: DBus.BusType.Session
        service: "org.freedesktop.Akonadi.Resource.akonadi_google_resource_0"
        path: "/"
        iface: "org.freedesktop.Akonadi.Agent.Status"
        function dbusstatus(status, message) {
            if (Number(status) === 0) {
                completedSync.dbussynchronized();
            }
        }
    }

    P5Support.DataSource {
        id: detailsSource
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            if (source === calendar.taskDoneCommand) {
                calendar.taskDoneCommand = "";
                if (data["exit code"] !== 0 && calendar.taskDoneRevert) {
                    // Akonadi refused: show the real state again
                    calendar.allTasks = calendar.taskDoneRevert;
                }
                calendar.taskDoneRevert = null;
                connectSource(calendar.tasksCommand);
                return;
            }
            if (source === calendar.tasksCommand) {
                try {
                    calendar.allTasks = JSON.parse(data["stdout"]);
                } catch (e) {
                    calendar.allTasks = [];
                }
                return;
            }
            if (source !== calendar.detailsCommand) {
                return;
            }
            try {
                calendar.pendingDetails = JSON.parse(data["stdout"]);
            } catch (e) {
                calendar.pendingDetails = { found: false };
            }
            if (calendar.pendingEvent) {
                calendar.showPendingEvent();
            } else {
                // details arrived after the fallback timer showed the card
                calendar.eventDetails = calendar.pendingDetails;
            }
        }
    }

    Keys.onEscapePressed: event => {
        if (calendar.selectedEvent) {
            calendar.closeEvent();
            event.accepted = true;
        } else {
            event.accepted = false;
        }
    }

    PlasmaCalendar.EventPluginsManager {
        id: eventPluginsManager
        enabledPlugins: Plasmoid.configuration.enabledCalendarPlugins
    }

    PlasmaCalendar.Calendar {
        id: backend

        days: 7
        weeks: 6
        firstDayOfWeek: Plasmoid.configuration.firstDayOfWeek > -1
            ? Plasmoid.configuration.firstDayOfWeek
            : Qt.locale().firstDayOfWeek
        today: root.currentTime

        Component.onCompleted: {
            daysModel.setPluginsManager(eventPluginsManager);
            detailsSource.connectSource(calendar.tasksCommand);
            calendar.updateDayEvents();
        }
    }

    Connections {
        target: backend.daysModel

        function onAgendaUpdated(updatedDate: date) {
            if (calendar.sameUtcDay(updatedDate, calendar.currentDate)) {
                calendar.updateDayEvents();
            }
        }
    }

    // Google-style task mark: an empty ring, or a filled one with a tick.
    component TaskMark: Rectangle {
        id: taskMark
        property bool done: false
        signal toggled()
        implicitWidth: Math.round(Kirigami.Units.iconSizes.small * 0.8)
        implicitHeight: implicitWidth
        radius: width / 2
        color: done ? calendar.taskColor
             : markMouse.containsMouse ? Qt.alpha(calendar.taskColor, 0.35) : "transparent"
        border.width: done ? 0 : 1.5
        border.color: calendar.taskColor
        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
        MouseArea {
            id: markMouse
            anchors.fill: parent
            anchors.margins: -Kirigami.Units.smallSpacing
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: taskMark.toggled()
        }
        PlasmaComponents.ToolTip.text: done ? "Отметить невыполненной" : "Отметить выполненной"
        PlasmaComponents.ToolTip.visible: markMouse.containsMouse
        PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
        Kirigami.Icon {
            anchors.centerIn: parent
            visible: parent.done
            width: parent.width * 0.75
            height: width
            source: "checkmark"
            color: Kirigami.Theme.backgroundColor
            isMask: true
        }
    }

    // Fixed-width slot in front of card rows: centres a dot, ring or icon on
    // the first text line so all row texts start at the same x.
    component LeadSlot: Item {
        property real lineHeight: bodyMetrics.height
        default property alias content: slotContent.data
        Layout.alignment: Qt.AlignTop
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: lineHeight
        Item {
            id: slotContent
            anchors.centerIn: parent
            width: childrenRect.width
            height: childrenRect.height
        }
    }

    FontMetrics {
        id: bodyMetrics
        font: Kirigami.Theme.defaultFont
    }

    component DetailRow: RowLayout {
        id: detailRow
        property string iconName
        property string text
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.largeSpacing
        visible: text !== ""
        LeadSlot {
            Kirigami.Icon {
                width: Kirigami.Units.iconSizes.small
                height: width
                source: detailRow.iconName
                opacity: 0.6
            }
        }
        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: detailRow.text
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }
    }

    header: Item {}

    // Leading column: the selected day
    // ================================
    ColumnLayout {
        id: leadingColumn

        opacity: (1 - calendar.cardShown) * calendar.dayFade
        visible: opacity > 0

        anchors {
            top: parent.top
            left: parent.left
            right: mainSeparator.left
            bottom: parent.bottom
            leftMargin: calendar.paddings
            rightMargin: calendar.paddings
        }
        spacing: Kirigami.Units.smallSpacing

        // Tasks and all-day events
        Flow {
            id: allDayFlow
            Layout.fillWidth: true
            Layout.topMargin: calendar.paddings
            spacing: Kirigami.Units.smallSpacing
            visible: (calendar.dayEvents.allDay ?? []).length + (calendar.dayEvents.tasks ?? []).length > 0

            Repeater {
                model: calendar.dayEvents.tasks ?? []
                delegate: Rectangle {
                    id: taskChip
                    required property var modelData

                    width: Math.min(taskRow.implicitWidth + Kirigami.Units.largeSpacing * 2, leadingColumn.width)
                    height: taskRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: height / 2
                    color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, calendar.taskColor,
                                                                   taskMouse.containsMouse ? 0.24 : 0.16)
                    opacity: modelData.completed ? 0.6 : 1
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                    RowLayout {
                        id: taskRow
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        TaskMark {
                            done: taskChip.modelData.completed
                            onToggled: calendar.setTaskDone(taskChip.modelData, !taskChip.modelData.completed)
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: taskChip.modelData.title
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            font.strikeout: taskChip.modelData.completed
                        }
                        PlasmaComponents.Label {
                            visible: taskChip.modelData.overdue
                            text: "с " + Qt.locale().toString(new Date(taskChip.modelData.startMs), "d MMM")
                            textFormat: Text.PlainText
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            color: Kirigami.Theme.negativeTextColor
                        }
                    }
                    MouseArea {
                        id: taskMouse
                        z: -1
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendar.openEvent(taskChip.modelData)
                    }
                }
            }

            Repeater {
                model: calendar.dayEvents.allDay ?? []
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property color dotColor: calendar.softColor(modelData.color)

                    width: Math.min(chipRow.implicitWidth + Kirigami.Units.largeSpacing * 2, leadingColumn.width)
                    height: chipRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: height / 2
                    color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, dotColor, 0.16)

                    RowLayout {
                        id: chipRow
                        anchors.fill: parent
                        anchors.leftMargin: Kirigami.Units.largeSpacing
                        anchors.rightMargin: Kirigami.Units.largeSpacing
                        spacing: Kirigami.Units.smallSpacing
                        Rectangle {
                            implicitWidth: Kirigami.Units.smallSpacing * 2
                            implicitHeight: implicitWidth
                            radius: width / 2
                            color: chip.dotColor
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: chip.modelData.title
                            textFormat: Text.PlainText
                            elide: Text.ElideRight
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendar.openEvent(chip.modelData)
                    }
                }
            }
        }

        // Hour timeline
        PlasmaComponents.ScrollView {
            id: timelineView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: allDayFlow.visible ? Kirigami.Units.largeSpacing : calendar.paddings
            PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

            Flickable {
                id: timeline

                readonly property real labelWidth: hourMetrics.width + Kirigami.Units.largeSpacing
                readonly property bool showsToday: calendar.sameDay(calendar.currentDate, root.currentTime)
                readonly property real nowHours: root.currentTime.getHours() + root.currentTime.getMinutes() / 60

                contentWidth: width
                contentHeight: calendar.hourHeight * 24 + hourMetrics.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // Show the first event or the current hour, not midnight.
                function scrollToInteresting() {
                    let hour = 8;
                    const timed = calendar.dayEvents.timed ?? [];
                    if (calendar.selectedEvent && !calendar.selectedEvent.allDay) {
                        hour = Math.max(0, calendar.selectedEvent.start - 0.75);
                    } else if (showsToday) {
                        hour = Math.max(0, nowHours - 1.5);
                    } else if (timed.length) {
                        hour = Math.max(0, timed[0].start - 0.5);
                    }
                    contentY = Math.max(0, Math.min(hour * calendar.hourHeight, contentHeight - height));
                }
                onHeightChanged: scrollToInteresting()

                TextMetrics {
                    id: hourMetrics
                    font: Kirigami.Theme.smallFont
                    text: calendar.timeText(new Date(2000, 0, 1, 22, 0))
                }

                Item {
                    width: timeline.width
                    height: timeline.contentHeight
                    // labels are vertically centred on their line
                    y: hourMetrics.height / 2

                    Repeater {
                        model: 25
                        delegate: Item {
                            id: hourLine
                            required property int index
                            y: index * calendar.hourHeight
                            width: parent.width
                            height: 1

                            PlasmaComponents.Label {
                                anchors.verticalCenter: parent.verticalCenter
                                width: hourMetrics.width
                                horizontalAlignment: Text.AlignRight
                                text: calendar.timeText(new Date(2000, 0, 1, hourLine.index % 24, 0))
                                textFormat: Text.PlainText
                                font: Kirigami.Theme.smallFont
                                opacity: 0.5
                            }
                            Rectangle {
                                x: timeline.labelWidth
                                width: parent.width - x
                                height: 1
                                color: calendar.lineColor
                            }
                        }
                    }

                    Repeater {
                        model: calendar.dayEvents.timed ?? []
                        delegate: Rectangle {
                            id: block
                            required property var modelData
                            readonly property color barColor: calendar.softColor(modelData.color)
                            readonly property bool isSelected: !!calendar.selectedEvent
                                && calendar.selectedEvent.startMs === modelData.startMs
                                && calendar.selectedEvent.title === modelData.title
                            readonly property real laneWidth: (parent.width - timeline.labelWidth) / modelData.lanes
                            readonly property bool roomy: height >= blockTitle.implicitHeight + blockTime.implicitHeight + Kirigami.Units.smallSpacing * 2

                            x: timeline.labelWidth + modelData.lane * laneWidth + 1
                            y: modelData.start * calendar.hourHeight + 1
                            width: laneWidth - 3
                            height: Math.max((modelData.end - modelData.start) * calendar.hourHeight - 3,
                                             blockTitle.implicitHeight + Kirigami.Units.smallSpacing * 2)
                            radius: Kirigami.Units.cornerRadius
                            color: Kirigami.ColorUtils.linearInterpolation(Kirigami.Theme.backgroundColor, barColor,
                                                                           isSelected ? 0.38 : blockHover.hovered ? 0.3 : 0.22)
                            border.width: isSelected ? 1.5 : 0
                            border.color: calendar.accentColor
                            clip: true

                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                            Rectangle {
                                width: 3
                                height: parent.height
                                radius: 1.5
                                color: block.barColor
                            }

                            Column {
                                anchors {
                                    fill: parent
                                    leftMargin: Kirigami.Units.largeSpacing
                                    rightMargin: Kirigami.Units.smallSpacing
                                    topMargin: Kirigami.Units.smallSpacing
                                }
                                PlasmaComponents.Label {
                                    id: blockTitle
                                    width: parent.width
                                    text: block.modelData.title
                                    textFormat: Text.PlainText
                                    font.weight: Font.Medium
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                                PlasmaComponents.Label {
                                    id: blockTime
                                    width: parent.width
                                    visible: block.roomy
                                    text: `${block.modelData.startText} – ${block.modelData.endText}`
                                    textFormat: Text.PlainText
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    opacity: 0.7
                                    elide: Text.ElideRight
                                }
                            }

                            HoverHandler { id: blockHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: calendar.openEvent(block.modelData)
                            }
                        }
                    }

                    // "Now" line
                    Item {
                        visible: timeline.showsToday
                        x: timeline.labelWidth - 4
                        y: timeline.nowHours * calendar.hourHeight
                        width: parent.width - x
                        z: 2
                        Rectangle {
                            width: 8; height: 8; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: Kirigami.Theme.negativeTextColor
                        }
                        Rectangle {
                            x: 4
                            width: parent.width - 4
                            height: 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: Kirigami.Theme.negativeTextColor
                        }
                    }
                }
            }
        }

        // World clocks, only when several time zones are configured
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: calendar.paddings
            visible: calendar.showClocks
            spacing: Kirigami.Units.smallSpacing

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                implicitHeight: 1
                color: calendar.lineColor
            }

            Repeater {
                id: clocksRepeater
                model: calendar.showClocks ? calendar.clockZones : []
                delegate: RowLayout {
                    id: clockRow
                    required property string modelData
                    readonly property bool isCurrentTimeZone: tzClock.timeZone == root.currentTimeZone

                    Layout.fillWidth: true
                    Clock {
                        id: tzClock
                        timeZone: clockRow.modelData
                        trackSeconds: Plasmoid.configuration.showSeconds === 2
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: {
                            switch (Plasmoid.configuration.displayTimezoneFormat) {
                            case 0: return tzClock.timeZoneCode;
                            case 1: return TimeZonesI18n.i18nCity(tzClock.timeZone);
                            case 2: return tzClock.timeZoneOffset;
                            }
                        }
                        textFormat: Text.PlainText
                        font.weight: clockRow.isCurrentTimeZone ? Font.Medium : Font.Normal
                        elide: Text.ElideRight
                    }
                    PlasmaComponents.Label {
                        text: calendar.timeText(tzClock.dateTime)
                            + (clockRow.isCurrentTimeZone ? "" : "  " + root.formatOffset(tzClock.dateTime))
                        textFormat: Text.PlainText
                        opacity: clockRow.isCurrentTimeZone ? 1 : 0.75
                    }
                }
            }
        }
    }


    // Event card layer: back button, card, the day's events as rows.
    // Cross-fades with the day (leadingColumn) instead of jumping.
    ColumnLayout {
        id: cardLayer

        anchors {
            top: parent.top
            left: parent.left
            right: mainSeparator.left
            bottom: parent.bottom
            leftMargin: calendar.paddings
            rightMargin: calendar.paddings
        }
        spacing: Kirigami.Units.smallSpacing
        opacity: calendar.cardShown
        visible: opacity > 0
        transform: Translate { y: (1 - calendar.cardShown) * Kirigami.Units.gridUnit * 0.6 }

        Rectangle {
            id: backButton
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.leftMargin: -Kirigami.Units.smallSpacing
            implicitWidth: backRow.implicitWidth + Kirigami.Units.smallSpacing * 3
            implicitHeight: backRow.implicitHeight + Kirigami.Units.smallSpacing * 2
            radius: Kirigami.Units.cornerRadius
            color: backMouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, backMouse.pressed ? 0.1 : 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
            Accessible.role: Accessible.Button
            Accessible.name: "Назад"

            RowLayout {
                id: backRow
                anchors.verticalCenter: parent.verticalCenter
                x: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing
                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: implicitWidth
                    source: Qt.application.layoutDirection === Qt.RightToLeft ? "go-next" : "go-previous"
                }
                PlasmaComponents.Label {
                    text: Qt.locale().toString(calendar.currentDate, "d MMMM")
                    textFormat: Text.PlainText
                }
            }
            MouseArea {
                id: backMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: calendar.closeEvent()
            }
        }

    // Event card: takes the place of the day header, the timeline stays below
    PlasmaComponents.ScrollView {
        id: eventCard

        Layout.fillWidth: true
        Layout.preferredHeight: cardColumn.implicitHeight
        // when switching events the list below glides instead of jumping
        Behavior on Layout.preferredHeight {
            enabled: calendar.cardShown === 1
            NumberAnimation { duration: 170; easing.type: Easing.OutQuad }
        }
        // keep at least a few hours of the day visible under the card
        Layout.maximumHeight: Math.max(Kirigami.Units.gridUnit * 6, cardLayer.height - Kirigami.Units.gridUnit * 8)
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff
        // only for really long cards, not while the height glides
        PlasmaComponents.ScrollBar.vertical.policy: cardColumn.implicitHeight > Layout.maximumHeight
            ? PlasmaComponents.ScrollBar.AsNeeded : PlasmaComponents.ScrollBar.AlwaysOff

        readonly property var ev: calendar.shownEvent ?? ({})
        readonly property var info: calendar.eventDetails ?? ({})
        readonly property bool loaded: calendar.eventDetails !== null
        readonly property string description: (info.found ? info.description : ev.description) ?? ""
        readonly property var meetLink: (info.links ?? []).find(l => /meet\.google|zoom\.us|teams\.microsoft|telemost/.test(l)) ?? ""
        readonly property var people: {
            const list = (info.attendees ?? []).slice();
            const org = info.organizer;
            if (org && !list.some(a => a.email === org.email)) {
                list.unshift(Object.assign({}, org, { status: "ACCEPTED" }));
            }
            return list.map(a => Object.assign({}, a, { isOrganizer: !!org && a.email === org.email }));
        }

        ColumnLayout {
            id: cardColumn
            width: eventCard.availableWidth - Kirigami.Units.smallSpacing
            opacity: calendar.cardFade
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.largeSpacing
                LeadSlot {
                    lineHeight: titleMetrics.height
                    Rectangle {
                        width: Kirigami.Units.smallSpacing * 2.5
                        height: width
                        radius: width / 2
                        color: calendar.softColor(eventCard.ev.color)
                    }
                }
                FontMetrics {
                    id: titleMetrics
                    font: cardTitle.font
                }
                Kirigami.Heading {
                    id: cardTitle
                    Layout.fillWidth: true
                    level: 3
                    text: eventCard.ev.title ?? ""
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: {
                    if (!calendar.shownEvent) return "";
                    const day = Qt.locale().toString(new Date(eventCard.ev.startMs), "dddd, d MMMM");
                    if (eventCard.ev.isTask) {
                        return ["Задача", "срок: " + day, eventCard.ev.list].filter(x => x).join(" · ");
                    }
                    const time = eventCard.ev.allDay ? "весь день"
                        : `${calendar.timeText(new Date(eventCard.ev.startMs))} – ${calendar.timeText(new Date(eventCard.ev.endMs))}`;
                    return [day, time, eventCard.info.calendar ?? ""].filter(x => x).join(" · ");
                }
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                opacity: 0.7
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: !!eventCard.ev.isTask
                spacing: Kirigami.Units.largeSpacing
                LeadSlot {
                    TaskMark {
                        done: !!eventCard.ev.completed
                        onToggled: calendar.setTaskDone(eventCard.ev, !eventCard.ev.completed)
                    }
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: {
                        const ev = eventCard.ev;
                        if (!ev.isTask) return "";
                        if (ev.completed) {
                            return ev.completedOn
                                ? "Выполнена " + Qt.locale().toString(new Date(ev.completedOn + "T12:00:00"), "d MMMM")
                                : "Выполнена";
                        }
                        return ev.overdue
                            ? "Не выполнена, просрочена с " + Qt.locale().toString(new Date(ev.startMs), "d MMMM")
                            : "Не выполнена";
                    }
                    color: eventCard.ev.overdue ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                }
            }

            DetailRow {
                iconName: "mark-location"
                text: eventCard.info.location ?? ""
            }
            DetailRow {
                iconName: "view-refresh"
                text: eventCard.info.recurring ? "Повторяющееся событие" : ""
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: eventCard.description !== ""
                implicitHeight: descriptionText.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius
                color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
                TextEdit {
                    id: descriptionText
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    text: eventCard.description
                    textFormat: TextEdit.PlainText
                    wrapMode: TextEdit.Wrap
                    readOnly: true
                    selectByMouse: true
                    color: Kirigami.Theme.textColor
                    selectionColor: Kirigami.Theme.highlightColor
                    selectedTextColor: Kirigami.Theme.highlightedTextColor
                    font: Kirigami.Theme.defaultFont
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: eventCard.people.length > 0
                spacing: Kirigami.Units.largeSpacing
                LeadSlot {
                    Kirigami.Icon {
                        width: Kirigami.Units.iconSizes.small
                        height: width
                        source: "system-users"
                        opacity: 0.6
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: eventCard.people
                        delegate: RowLayout {
                            id: personRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: personRow.modelData.name || personRow.modelData.email
                                textFormat: Text.PlainText
                                elide: Text.ElideRight
                                PlasmaComponents.ToolTip.text: personRow.modelData.email
                                PlasmaComponents.ToolTip.visible: personHover.hovered && personRow.modelData.name !== ""
                                HoverHandler { id: personHover }
                            }
                            PlasmaComponents.Label {
                                text: personRow.modelData.isOrganizer ? "организатор" : calendar.attendeeStatus(personRow.modelData.status)
                                textFormat: Text.PlainText
                                opacity: 0.55
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }
                    }
                }
            }

            PlasmaComponents.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                visible: !eventCard.loaded
                text: "Загружаю подробности…"
                opacity: 0.5
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }

            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                // Flow keeps the height of hidden buttons; tasks have none
                visible: eventCard.meetLink !== "" || (eventCard.info.googleUrl ?? "") !== ""
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Button {
                    visible: eventCard.meetLink !== ""
                    icon.name: "camera-video"
                    text: "Подключиться"
                    onClicked: Qt.openUrlExternally(eventCard.meetLink)
                }
                PlasmaComponents.Button {
                    visible: (eventCard.info.googleUrl ?? "") !== ""
                    icon.name: "globe"
                    text: "Открыть в Google"
                    onClicked: Qt.openUrlExternally(eventCard.info.googleUrl)
                }
            }
        }
    }

    // Separates the event card from the day below it
    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing
        implicitHeight: 1
        color: calendar.lineColor
    }

    // Under the event card: the day's events as rows, then the next day
    PlasmaComponents.ScrollView {
        id: cardDayList
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: calendar.paddings
        PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

        TextMetrics {
            id: rangeMetrics
            font: Kirigami.Theme.smallFont
            text: calendar.timeText(new Date(2000, 0, 1, 22, 40)) + "–" + calendar.timeText(new Date(2000, 0, 1, 23, 40))
        }

        ColumnLayout {
            width: cardDayList.availableWidth - Kirigami.Units.smallSpacing
            spacing: 2

            Repeater {
                model: calendar.cardDays
                delegate: ColumnLayout {
                    id: dayBlock
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: 2

                    PlasmaComponents.Label {
                        Layout.topMargin: dayBlock.index > 0 ? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing
                        Layout.bottomMargin: 2
                        text: {
                            const all = dayBlock.modelData.events;
                            const t = all.filter(e => e.isTask).length, n = all.length - t;
                            const parts = [dayBlock.modelData.title];
                            if (n) parts.push(`${n} ${calendar.eventsWord(n)}`);
                            if (t) parts.push(`${t} ${calendar.tasksWord(t)}`);
                            if (!n && !t) parts.push("нет событий");
                            return parts.join(" · ").toUpperCase();
                        }
                        textFormat: Text.PlainText
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        font.letterSpacing: 0.5
                        opacity: 0.5
                    }

                    Repeater {
                        model: dayBlock.modelData.events
                        delegate: Rectangle {
                            id: dayRow
                            required property var modelData
                            readonly property bool isSelected: !!calendar.shownEvent
                                && calendar.shownEvent.startMs === modelData.startMs
                                && calendar.shownEvent.title === modelData.title

                            Layout.fillWidth: true
                            implicitHeight: rowLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.cornerRadius
                            color: isSelected ? Qt.alpha(Kirigami.Theme.textColor, 0.08)
                                 : rowMouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.04) : "transparent"
                            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                            RowLayout {
                                id: rowLayout
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.smallSpacing
                                anchors.rightMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Rectangle {
                                    implicitWidth: 3
                                    Layout.fillHeight: true
                                    Layout.topMargin: 1
                                    Layout.bottomMargin: 1
                                    radius: 1.5
                                    color: calendar.softColor(dayRow.modelData.color)
                                }
                                PlasmaComponents.Label {
                                    Layout.preferredWidth: rangeMetrics.width + Kirigami.Units.smallSpacing
                                    text: dayRow.modelData.isTask ? (dayRow.modelData.overdue ? "просрочена" : "задача")
                                        : dayRow.modelData.allDay ? "весь день"
                                        : `${dayRow.modelData.startText}–${dayRow.modelData.endText}`
                                    textFormat: Text.PlainText
                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                    font.features: { "tnum": 1 }
                                    opacity: 0.7
                                }
                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: dayRow.modelData.title
                                    font.strikeout: !!dayRow.modelData.completed
                                    opacity: dayRow.modelData.completed ? 0.6 : 1
                                    textFormat: Text.PlainText
                                    elide: Text.ElideRight
                                    font.weight: dayRow.isSelected ? Font.Medium : Font.Normal
                                }
                            }
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: calendar.openEvent(dayRow.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
    }

    // Vertical separator
    Rectangle {
        id: mainSeparator
        anchors {
            top: parent.top
            right: monthColumn.left
            bottom: parent.bottom
            // Stretch to the top of the dialog, as the stock separator did.
            topMargin: calendar.parent ? -calendar.parent.y : 0
        }
        width: 1
        color: calendar.lineColor
    }

    // Trailing column: month
    // ======================
    ColumnLayout {
        id: monthColumn

        anchors {
            top: parent.top
            right: parent.right
            bottom: parent.bottom
            leftMargin: calendar.paddings
        }
        width: Math.round(calendar.width * 0.48)
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: calendar.paddings
            spacing: 0

            Kirigami.Heading {
                Layout.fillWidth: true
                level: 3
                opacity: calendar.monthFade
                text: calendar.capitalize(Qt.locale().standaloneMonthName(backend.displayedDate.getMonth(), Locale.LongFormat))
                    + (backend.displayedDate.getFullYear() !== root.currentTime.getFullYear() ? " " + backend.displayedDate.getFullYear() : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }
            PlasmaComponents.ToolButton {
                icon.name: Qt.application.layoutDirection === Qt.RightToLeft ? "go-next" : "go-previous"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: "Предыдущий месяц"
                onClicked: calendar.changeMonth(-1)
            }
            PlasmaComponents.ToolButton {
                text: "Сегодня"
                onClicked: calendar.selectDate(root.currentTime)
            }
            PlasmaComponents.ToolButton {
                icon.name: Qt.application.layoutDirection === Qt.RightToLeft ? "go-previous" : "go-next"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: "Следующий месяц"
                onClicked: calendar.changeMonth(1)
            }
            PlasmaComponents.ToolButton {
                id: configureButton
                visible: Plasmoid.internalAction("configure").enabled
                icon.name: "configure"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: Plasmoid.internalAction("configure").text
                onClicked: Plasmoid.internalAction("configure").trigger()
                PlasmaComponents.ToolTip { text: configureButton.text }
            }
            PlasmaComponents.ToolButton {
                id: pinButton
                checkable: true
                checked: Plasmoid.configuration.pin
                icon.name: "window-pin"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: "Не закрывать"
                onToggled: Plasmoid.configuration.pin = checked
                PlasmaComponents.ToolTip { text: pinButton.text }
            }
        }

        GridLayout {
            id: monthGrid
            opacity: calendar.monthFade

            readonly property real cellHeight: Math.max(Kirigami.Units.gridUnit * 1.9,
                Math.min(Kirigami.Units.gridUnit * 2.6, (monthColumn.height - y - dayHeader.implicitHeight - Kirigami.Units.largeSpacing * 2
                    - calendar.paddings * 2 - weekdayMetrics.height * 2) / 6))

            Layout.fillWidth: true
            Layout.leftMargin: calendar.paddings
            Layout.rightMargin: calendar.paddings
            Layout.topMargin: Kirigami.Units.smallSpacing
            columns: 7
            rowSpacing: 2
            columnSpacing: 2

            TextMetrics {
                id: weekdayMetrics
                font: Kirigami.Theme.smallFont
                text: "пн"
            }

            Repeater {
                model: 7
                delegate: PlasmaComponents.Label {
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((backend.firstDayOfWeek + index) % 7, Locale.ShortFormat).toLowerCase()
                    textFormat: Text.PlainText
                    font: Kirigami.Theme.smallFont
                    opacity: 0.5
                }
            }

            Repeater {
                model: backend.daysModel
                delegate: Item {
                    id: cell

                    required property int index
                    required property var model

                    readonly property date thisDate: new Date(model.yearNumber, model.monthNumber - 1, model.dayNumber)
                    readonly property bool isToday: calendar.sameDay(thisDate, root.currentTime)
                    readonly property bool isSelected: calendar.sameDay(thisDate, calendar.currentDate)
                    readonly property bool isWeekend: [0, 6].includes(thisDate.getDay())
                    // eventCount changes when plugin data arrives, which re-evaluates this.
                    readonly property var dotColors: (calendar.allTasks.length >= 0 && (model.eventCount ?? 0) > 0)
                        || calendar.tasksForDay(thisDate).length ? calendar.dayColors(thisDate) : []

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: monthGrid.cellHeight

                    Rectangle {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, monthGrid.cellHeight * 1.15)
                        height: parent.height
                        radius: Kirigami.Units.cornerRadius
                        color: cell.isToday ? calendar.accentColor
                             : dayMouse.containsMouse ? Qt.alpha(Kirigami.Theme.textColor, 0.06)
                             : "transparent"
                        border.width: cell.isSelected && !cell.isToday ? 1.5 : 0
                        border.color: calendar.accentColor
                        Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                    }

                    PlasmaComponents.Label {
                        id: dayLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -Kirigami.Units.smallSpacing / 2
                        text: cell.model.dayNumber
                        textFormat: Text.PlainText
                        font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        color: cell.isToday ? Kirigami.Theme.backgroundColor : Kirigami.Theme.textColor
                        opacity: !cell.model.isCurrent && !cell.isToday ? 0.35 : cell.isWeekend && !cell.isToday ? 0.7 : 1
                    }

                    Row {
                        anchors.top: dayLabel.bottom
                        anchors.topMargin: 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        opacity: cell.model.isCurrent ? 1 : 0.5
                        visible: cell.dotColors.length > 0

                        Repeater {
                            model: cell.dotColors
                            delegate: Rectangle {
                                required property string modelData
                                width: 4
                                height: 4
                                radius: 2
                                color: cell.isToday ? Kirigami.Theme.backgroundColor : calendar.softColor(modelData)
                            }
                        }
                    }

                    MouseArea {
                        id: dayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: calendar.selectDate(cell.thisDate)
                    }
                }
            }
        }

        // The selected day, in the free space under the month (rev 51)
        RowLayout {
            id: dayHeader
            opacity: calendar.dayFade
            Layout.fillWidth: true
            Layout.leftMargin: calendar.paddings + Kirigami.Units.smallSpacing
            Layout.rightMargin: calendar.paddings
            Layout.topMargin: Kirigami.Units.largeSpacing * 2
            Layout.bottomMargin: calendar.paddings
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                text: calendar.currentDate.getDate()
                textFormat: Text.PlainText
                font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 3)
                font.weight: Font.Light
                Layout.alignment: Qt.AlignBottom
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: Kirigami.Units.smallSpacing
                spacing: 0

                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: Qt.locale().toString(calendar.currentDate,
                        calendar.currentDate.getFullYear() === root.currentTime.getFullYear() ? "MMMM" : "MMMM yyyy")
                    textFormat: Text.PlainText
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: {
                        const weekday = Qt.locale().toString(calendar.currentDate, "dddd");
                        const n = calendar.dayEvents.count ?? 0;
                        const t = (calendar.dayEvents.tasks ?? []).length;
                        const parts = [];
                        if (n > 0) parts.push(`${n} ${calendar.eventsWord(n)}`);
                        if (t > 0) parts.push(`${t} ${calendar.tasksWord(t)}`);
                        return [weekday].concat(parts.length ? parts : ["нет событий"]).join(" · ");
                    }
                    textFormat: Text.PlainText
                    opacity: 0.7
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideRight
                }
            }

            PlasmaComponents.ToolButton {
                id: addEventButton
                Layout.alignment: Qt.AlignVCenter
                visible: ApplicationIntegration.calendarInstalled
                icon.name: "list-add"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: "Новое событие"
                onClicked: ApplicationIntegration.launchCalendar()
                PlasmaComponents.ToolTip { text: addEventButton.text }
            }
        }

        Item { Layout.fillHeight: true }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: wheel => {
                if (wheel.angleDelta.y > 0) {
                    calendar.changeMonth(-1);
                } else if (wheel.angleDelta.y < 0) {
                    calendar.changeMonth(1);
                }
            }
        }
    }
}
