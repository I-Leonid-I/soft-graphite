/*
    SPDX-FileCopyrightText: 2016 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2020 Nate Graham <nate@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasmoid

Item {
    id: popup
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    // Use the active scroll view's actual content, including its own header
    // and footer. Never derive the preferred size from the stretched viewport.
    readonly property Item representation: systemTrayState.activeApplet?.fullRepresentationItem ?? null
    function naturalBodyHeight(item, depth) {
        if (!item || depth > 12 || item instanceof QQC2.ScrollBar) return 0;
        if (!item.visible) return 0;
        if (item instanceof Flickable || item instanceof QQC2.ScrollView) {
            const offset = item.mapToItem(popup.representation, 0, 0).y;
            let placeholderH = 0;
            const target = (item instanceof QQC2.ScrollView && item.contentItem) ? item.contentItem : item;
            for (const child of target.children) {
                if (child.visible && child.implicitHeight > 0) {
                    placeholderH = Math.max(placeholderH, child.implicitHeight);
                }
            }
            return Math.max(0, offset) + Math.max(placeholderH, item.contentHeight);
        }
        let height = 0;
        for (const child of item.children) height = Math.max(height, naturalBodyHeight(child, depth + 1));
        return height;
    }
    property real graphiteNaturalHeight: 210
    function measureNaturalHeight() {
        if (!representation) return compactHeight;
        const footer = representation.footer?.visible ? representation.footer.height : 0;
        const body = naturalBodyHeight(representation, 0);
        const content = body > 0 ? body + footer + (representation.bottomPadding ?? 0) : Math.max(180, representation.implicitHeight);
        return Math.ceil(trayHeading.implicitHeight + expandedRepresentation.spacing + (container.mergeHeadings ? 0 : dialog.topPadding) + Math.max(160, content) + 12);
    }
    // Measure after Qt's layout pass, so resizing the popup cannot recursively
    // evaluate a ScrollBar's visibility binding. No recurring timer or polling.
    Timer {
        id: sizePass
        interval: 0
        onTriggered: if (popup.visible) {
            popup.graphiteNaturalHeight = popup.measureNaturalHeight();
        }
    }
    Connections {
        target: popup.representation
        function onWidthChanged() { sizePass.restart(); }
        function onHeightChanged() { sizePass.restart(); }
        function onVisibleChanged() { sizePass.restart(); }
    }
    readonly property real desiredHeight: measureNaturalHeight()
    onDesiredHeightChanged: sizePass.restart()
    function separateTextRows(item, depth) {
        if (!item || depth > 14 || !item.visible) return;
        if (item instanceof ColumnLayout && item.spacing === 0) {
            const children = Array.from(item.children).filter(c => c.visible && c.implicitHeight > 0);
            if (children.length >= 2 && children.every(c => typeof c.text === "string" && c.font !== undefined)) item.spacing = 3;
        }
        for (const child of item.children) separateTextRows(child, depth + 1);
    }
    // One coalesced pass on opening or content changes, never a repeating timer.
    onRepresentationChanged: { sizePass.restart(); textSpacingPass.restart(); }
    onGraphiteNaturalHeightChanged: textSpacingPass.restart()
    onVisibleChanged: if (visible) {
        sizePass.restart();
        textSpacingPass.restart();
    }
    Timer {
        id: textSpacingPass
        interval: 0
        onTriggered: if (popup.visible) popup.separateTextRows(popup.representation, 0)
    }
    readonly property int fittedHeight: Math.min(Math.round(root.screenGeometry.height * 0.60), Math.max(210, graphiteNaturalHeight))
    Layout.minimumWidth: systemTrayState.activeApplet ? 400 : 320
    Layout.preferredWidth: Layout.minimumWidth
    Layout.maximumWidth: Layout.minimumWidth
    Layout.minimumHeight: systemTrayState.activeApplet ? fittedHeight : popup.compactHeight
    Layout.preferredHeight: Layout.minimumHeight
    Layout.maximumHeight: Layout.minimumHeight

    readonly property int compactHeight: {
        const count = hiddenLayout?.count ?? 0;
        const rows = Math.ceil(count / 2);
        const cellH = hiddenItemsView.layout?.delegateHeight ?? 44;
        const headerH = trayHeading.implicitHeight + expandedRepresentation.spacing + (hiddenItemsView.Layout.topMargin ?? 0) + 12;
        return Math.max(120, Math.min(Math.round(root.screenGeometry.height * 0.65), headerH + (rows * cellH)));
    }

    property alias hiddenLayout: hiddenItemsView.layout
    property alias plasmoidContainer: container

    // Header
    PlasmaExtras.PlasmoidHeading {
        id: plasmoidHeading
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: trayHeading.height + bottomPadding + container.headingHeight
        Behavior on height {
            NumberAnimation { duration: Kirigami.Units.shortDuration / 2; easing.type: Easing.InOutQuad }
        }
    }

    // Main content layout
    ColumnLayout {
        id: expandedRepresentation
        anchors.fill: parent
        // TODO: remove this so the scrollview fully touches the header;
        // add top padding internally
        spacing: 8

        // Header content layout
        RowLayout {
            id: trayHeading
            spacing: 4
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            Layout.fillWidth: true

            PlasmaComponents.ToolButton {
                id: backButton
                visible: systemTrayState.activeApplet && systemTrayState.activeApplet.expanded && (popup.hiddenLayout.itemCount > 0)
                icon.name: mirrored ? "go-previous-symbolic-rtl" : "go-previous-symbolic"

                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18ndc("plasma_applet_org.kde.plasma.systemtray", "@action:button", "Go Back")

                KeyNavigation.down: hiddenItemsView.visible ? popup.hiddenLayout : container

                onClicked: if (typeof systemTrayState.activeApplet?.backAction !== "undefined" && systemTrayState.activeApplet.backAction.enabled) {
                    systemTrayState.activeApplet?.backAction.trigger()
                } else {
                    systemTrayState.setActiveApplet(null)
                }
            }

            Kirigami.Heading {
                Layout.fillWidth: true
                leftPadding: systemTrayState.activeApplet ? 0 : Kirigami.Units.largeSpacing

                level: 1
                font: Qt.font({family: "Fira Sans", pixelSize: 13, weight: Font.Normal})
                text: systemTrayState.activeApplet ? systemTrayState.activeApplet.plasmoid.title : (Qt.locale().name.startsWith("ru") ? "Система" : "System")
                maximumLineCount: 1
                textFormat: Text.PlainText
                elide: Text.ElideRight
            }

            Repeater {
                id: primaryActionButtons

                model: {
                    if (actionsButton.applet === null) {
                        return [];
                    }
                    return actionsButton.applet.Plasmoid.contextualActions.filter(action => {
                        return !action.isSeparator && action.priority === PlasmaCore.Action.HighPriority;
                    });
                }

                delegate: PlasmaComponents.ToolButton {
                    id: actionButton
                    required property int index
                    required property PlasmaCore.Action modelData
                    // We cannot use `action` as it is already a QQuickAction property of the button
                    property PlasmaCore.Action qAction: modelData

                    visible: qAction && qAction.visible

                    // NOTE: it needs an IconItem because QtQuickControls2 buttons cannot load QIcons as their icon
                    contentItem: Kirigami.Icon {
                        anchors.centerIn: parent
                        active: actionButton.hovered
                        implicitWidth: Kirigami.Units.iconSizes.smallMedium
                        implicitHeight: implicitWidth
                        source: actionButton.qAction ? actionButton.qAction.icon.name : ""
                    }

                    enabled: qAction && qAction.enabled
                    checkable: qAction && qAction.checkable
                    checked: qAction && qAction.checked
                    display: PlasmaComponents.AbstractButton.IconOnly
                    text: qAction ? qAction.text : ""

                    KeyNavigation.down: backButton.KeyNavigation.down
                    KeyNavigation.left: (index > 0) ? primaryActionButtons.itemAt(index - 1) : backButton
                    KeyNavigation.right: (index < primaryActionButtons.count - 1) ? primaryActionButtons.itemAt(index + 1) :
                                                            actionsButton.visible ? actionsButton : actionsButton.KeyNavigation.right

                    PlasmaComponents.ToolTip {
                        text: actionButton.text
                    }

                    onClicked: {
                        if (qAction) {
                            qAction.trigger();
                        }
                    }
                }
            }

            PlasmaComponents.ToolButton {
                id: actionsButton
                visible: visibleActions > 0
                enabled: visibleActions > 0 && (singleAction ? singleAction.enabled : true)
                checked: (visibleActions > 1 || !singleAction) ? configMenu.status !== PlasmaExtras.Menu.Closed : (singleAction && singleAction.checked)
                property QtObject applet: systemTrayState.activeApplet || root
                property int visibleActions: actions.length
                property PlasmaCore.Action singleAction: visibleActions === 1 && menuItemFactory.object && !menuItemFactory.object.action.alwaysShowAsMenu ? menuItemFactory.object.action : null

                readonly property var actions: {
                    if (!applet) {
                        return [];
                    }

                    return applet.plasmoid.contextualActions
                        .filter(action => {
                            return action.visible &&
                            action.priority === PlasmaCore.Action.NormalPriority &&
                            action !== applet.plasmoid.internalAction("configure");
                        })
                        // squash separators
                        .reduce((dstActions, action, i, srcActions) => {
                            if (!action.isSeparator) {
                                const prevAction = srcActions[i - 1];
                                if (prevAction?.isSeparator && dstActions.length > 0) {
                                    dstActions.push(prevAction);
                                }
                                dstActions.push(action);
                            }
                            return dstActions;
                        }, []);
                }

                icon.name: "application-menu"
                checkable: (visibleActions > 1 || !singleAction) || (singleAction && singleAction.checkable)
                contentItem.opacity: (visibleActions > 1 || !singleAction) ? 1 : 0

                display: PlasmaComponents.AbstractButton.IconOnly
                text: actionsButton.singleAction ? actionsButton.singleAction.text : i18nd("plasma_applet_org.kde.plasma.systemtray", "More actions")

                Accessible.role: actionsButton.singleAction ? Accessible.Button : Accessible.ButtonMenu

                KeyNavigation.down: backButton.KeyNavigation.down
                KeyNavigation.right: configureButton.visible ? configureButton : configureButton.KeyNavigation.right

                // NOTE: it needs a Kirigami.Icon because QtQuickControls2 buttons cannot load QIcons as their icon
                Kirigami.Icon {
                    parent: actionsButton
                    anchors.centerIn: parent
                    active: actionsButton.hovered
                    implicitWidth: Kirigami.Units.iconSizes.smallMedium
                    implicitHeight: implicitWidth
                    source: actionsButton.singleAction !== null ? actionsButton.singleAction.icon.name : ""
                    visible: actionsButton.singleAction
                }
                onToggled: {
                    if (visibleActions > 1 || !singleAction) {
                        if (checked) {
                            configMenu.openRelative();
                        } else {
                            configMenu.close();
                        }
                    }
                }
                onClicked: {
                    if (singleAction) {
                        singleAction.trigger();
                    } else {
                        configMenu.openRelative();
                    }
                }
                PlasmaComponents.ToolTip {
                    text: actionsButton.text
                }
                PlasmaExtras.Menu {
                    id: configMenu
                    visualParent: actionsButton
                    placement: PlasmaExtras.Menu.BottomPosedLeftAlignedPopup
                }

                Instantiator {
                    id: menuItemFactory

                    model: actionsButton.actions

                    delegate: PlasmaExtras.MenuItem {
                        id: menuItem
                        required property PlasmaCore.Action modelData
                        action: modelData
                    }

                    onObjectAdded: (index, object) => {
                        configMenu.addMenuItem(object);
                    }

                    onObjectRemoved: (index, object) => {
                        configMenu.removeMenuItem(object)
                    }
                }
            }
            PlasmaComponents.ToolButton {
                id: configureButton
                icon.name: "configure"
                visible: actionsButton.applet && actionsButton.applet.plasmoid.internalAction("configure")

                display: PlasmaComponents.AbstractButton.IconOnly
                text: actionsButton.applet?.plasmoid.internalAction("configure")?.text ?? ""

                KeyNavigation.down: backButton.KeyNavigation.down
                KeyNavigation.left: actionsButton.visible ? actionsButton : actionsButton.KeyNavigation.left
                KeyNavigation.right: pinButton

                PlasmaComponents.ToolTip {
                    text: parent.visible ? parent.text : ""
                }
                onClicked: actionsButton.applet.plasmoid.internalAction("configure").trigger();
            }

            PlasmaComponents.ToolButton {
                id: pinButton
                checkable: true
                checked: Plasmoid.configuration.pin
                onToggled: Plasmoid.configuration.pin = checked
                icon.name: "window-pin"

                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18nd("plasma_applet_org.kde.plasma.systemtray", "Keep Open")

                KeyNavigation.down: backButton.KeyNavigation.down
                KeyNavigation.left: configureButton.visible ? configureButton : configureButton.KeyNavigation.left
                KeyNavigation.tab: hiddenItemsView.visible ? hiddenItemsView.layout : container.currentItem?.nextItemInFocusChain() ?? null

                PlasmaComponents.ToolTip {
                    text: parent.text
                }
            }
        }

        // Grid view of all available items
        HiddenItemsView {
            id: hiddenItemsView
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            visible: !systemTrayState.activeApplet

            KeyNavigation.up: pinButton

            onVisibleChanged: {
                if (visible) {
                    layout.forceActiveFocus();
                    systemTrayState.oldVisualIndex = systemTrayState.newVisualIndex = -1;
                }
            }
        }

        // Container for currently visible item
        PlasmoidPopupsContainer {
            id: container
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: systemTrayState.activeApplet

            // We need to add margin on the top so it matches the dialog's own margin
            Layout.topMargin: mergeHeadings ? 0 : dialog.topPadding

            KeyNavigation.up: pinButton
            KeyNavigation.backtab: pinButton

            onVisibleChanged: {
                if (visible) {
                    forceActiveFocus();
                }
            }
        }
    }

    // Footer
    PlasmaExtras.PlasmoidHeading {
        id: plasmoidFooter
        position: PlasmaComponents.ToolBar.Footer
        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
        visible: container.appletHasFooter
        height: container.footerHeight
        // So that it doesn't appear over the content view, which results in
        // the footer controls being inaccessible
        z: -9999
    }
}
