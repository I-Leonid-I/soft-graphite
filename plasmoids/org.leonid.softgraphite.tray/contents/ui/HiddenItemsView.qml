/*
    SPDX-FileCopyrightText: 2016 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2020 Konrad Materka <materka@gmail.com>
    SPDX-FileCopyrightText: 2020 Nate Graham <nate@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras

PlasmaComponents3.ScrollView {
    id: hiddenTasksView
    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

    property alias layout: hiddenTasks

    hoverEnabled: true
    background: null

    GridView {
        id: hiddenTasks

        readonly property int columns: 2
        readonly property int minimumColumns: 4

        // Keep these in sync with ItemLoader.qml
        readonly property int delegateMaxTextLines: 2
        readonly property int delegateMargins: Kirigami.Units.smallSpacing

        readonly property int delegateHeight: Math.max(44, Math.ceil((metrics.height * delegateMaxTextLines) + (delegateMargins * 2)))

        // Accessible.List as role is not optimal here as it's not clear it's a grid, and there is no grid role
        Accessible.description: i18ndc("plasma_applet_org.kde.plasma.systemtray", "@info:whatsthis accessible description for popup grid", "Grid with %1 items in %2 columns", hiddenTasks.count, columns)

        TextMetrics {
            id: metrics
            font: Qt.font({family: "Fira Sans", pixelSize: 13})
            text: i18ndc("plasma_applet_org.kde.plasma.systemtray", "Some letters with tall characters, ascenders, descenders, etc", "AILlmyjgGJP")
        }

        width: hiddenTasksView.availableWidth
        cellWidth: Math.floor(width / columns)
        cellHeight: delegateHeight

        currentIndex: -1
        highlight: PlasmaExtras.Highlight {}
        highlightMoveDuration: 0

        pixelAligned: true

        readonly property int itemCount: model.count

        model: root.hiddenModel
        delegate: ItemLoader {
            width: hiddenTasks.cellWidth
            height: hiddenTasks.cellHeight
            Accessible.role: Accessible.ListItem // needed to get the GridView description or role announced
        }

        keyNavigationEnabled: true
        activeFocusOnTab: true

        KeyNavigation.up: hiddenTasksView.KeyNavigation.up

        onActiveFocusChanged: {
            if (activeFocus && currentIndex === -1) {
                currentIndex = 0
            } else if (!activeFocus && currentIndex >= 0) {
                currentIndex = -1
            }
        }
    }
}
