/*
    SPDX-FileCopyrightText: 2013 Heena Mahour <heena393@gmail.com>
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "panelnative" as Native
import org.kde.taskmanager as TaskManager
// Deliberately imported after QtQuick to avoid missing restoreMode property in Binding. Fix in Qt 6.
import QtQml

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import plasma.applet.org.kde.plasma.appmenu

PlasmoidItem {
    id: root
    EdgeState { id: graphiteEdge; panelItem: root; screenGeometry: root.screenGeometry }

    TaskManager.TasksModel { id: applicationTasks; groupMode: TaskManager.TasksModel.GroupDisabled; filterByScreen: true; screenGeometry: root.screenGeometry }
    property string fallbackName: "Рабочий стол"
    property int namedPid: 0
    function updateName() {
        const pid=Number(graphiteEdge.current.pid || 0);
        for (let row=0; row<applicationTasks.rowCount(); ++row) {
            const idx=applicationTasks.index(row,0);
            if (Number(applicationTasks.data(idx,TaskManager.AbstractTasksModel.AppPid))===pid) {
                const name=applicationTasks.data(idx,TaskManager.AbstractTasksModel.AppName);
                if (name) { namedPid=pid; fallbackName=name; return; }
            }
        }
        // Transient photo/dialog windows retain their parent's application name.
        if (pid===namedPid && pid!==0) return;
        namedPid=pid;fallbackName=graphiteEdge.current.appName || "Рабочий стол";
    }
    Connections { target: graphiteEdge; function onCurrentChanged() { activeMenuRefresh.restart(); } }
    property int activePid: 0
    property string menuService: ""
    property string menuPath: ""
    function updateActiveMenu() {
        let idx=applicationTasks.activeTask;
        const targetPid=Number(graphiteEdge.current.pid || 0);
        if(Number(applicationTasks.data(idx,TaskManager.AbstractTasksModel.AppPid))!==targetPid){
            idx=applicationTasks.index(-1,0);
            for(let row=0;row<applicationTasks.rowCount();++row){
                const candidate=applicationTasks.index(row,0);
                if(Number(applicationTasks.data(candidate,TaskManager.AbstractTasksModel.AppPid))===targetPid){idx=candidate;break;}
            }
        }
        activePid=Number(applicationTasks.data(idx,TaskManager.AbstractTasksModel.AppPid)) || 0;
        menuService=applicationTasks.data(idx,TaskManager.AbstractTasksModel.ApplicationMenuServiceName) || "";
        menuPath=applicationTasks.data(idx,TaskManager.AbstractTasksModel.ApplicationMenuObjectPath) || "";
        updateName();
    }
    Timer { id: activeMenuRefresh; interval: 0; onTriggered: root.updateActiveMenu() }
    Connections {
        target: applicationTasks
        function onActiveTaskChanged(){activeMenuRefresh.restart();}
        function onDataChanged(){activeMenuRefresh.restart();}
        function onRowsInserted(){activeMenuRefresh.restart();}
        function onRowsRemoved(){activeMenuRefresh.restart();}
        function onModelReset(){activeMenuRefresh.restart();}
        function onLayoutChanged(){activeMenuRefresh.restart();}
    }
    Component.onCompleted: updateActiveMenu()
    readonly property bool menuMatchesWindow: !graphiteEdge.suppressed && root.activePid===Number(graphiteEdge.current.pid)

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool view: Plasmoid.configuration.compactView

    onViewChanged: {
        Plasmoid.view = view;
    }

    Plasmoid.constraintHints: Plasmoid.CanFillArea
    preferredRepresentation: Plasmoid.configuration.compactView ? compactRepresentation : fullRepresentation

    // Only exists because the default CompactRepresentation doesn't expose a
    // way to mark its icon as disabled.
    // TODO remove once it gains that feature.
    compactRepresentation: PlasmaComponents3.ToolButton {
        readonly property int fakeIndex: 0
        Layout.fillWidth: false
        Layout.fillHeight: false
        Layout.minimumWidth: implicitWidth
        Layout.maximumWidth: implicitWidth
        enabled: root.menuMatchesWindow && appMenuModel.menuAvailable
        checkable: appMenuModel.menuAvailable && Plasmoid.currentIndex === fakeIndex
        checked: checkable
        icon.name: "application-menu"

        display: PlasmaComponents3.AbstractButton.IconOnly
        text: Plasmoid.title
        Accessible.description: root.toolTipSubText

        onClicked: Plasmoid.trigger(this, 0);
    }

    fullRepresentation: Item {
        id: menuPresentation
        objectName: "graphite-menu-presentation"
        property bool ready: false
        property real naturalWidth: liveContents.implicitWidth
        property real measuredWidth: naturalWidth
        property real visualWidth: measuredWidth
        property real startWidth: measuredWidth
        property real endWidth: measuredWidth
        property var displayedRows: []
        property string displayedName: root.fallbackName
        property bool displayedFullscreen: graphiteEdge.fullscreen
        property int displayedPid: 0
        property string displayedKey: ""
        property string phase: "idle"
        property real blend: 1
        property int transitionCount: 0
        property var outgoingRows: []
        property string outgoingName: ""
        property bool outgoingFullscreen: false
        property bool animateCommit: false
        property double waitSince: 0
        implicitWidth: measuredWidth
        implicitHeight: liveContents.implicitHeight
        Layout.minimumWidth: measuredWidth
        Layout.preferredWidth: measuredWidth
        Layout.maximumWidth: measuredWidth
        Layout.minimumHeight: implicitHeight
        clip: true
        onBlendChanged: {
            if (phase==="morph") {
                visualWidth=startWidth+(endWidth-startWidth)*blend;
                Native.PanelTools.setMenuWidth(menuPresentation,visualWidth);
            }
        }
        // No transition to a temporary fallback while the new menu is importing.
        function desiredContent(allowFallback) {
            const pid=Number(graphiteEdge.current.pid || 0);
            if (!allowFallback && root.activePid && root.activePid!==pid) return null;
            const rows=root.menuMatchesWindow && appMenuModel.visible
                ? Native.PanelTools.menuSnapshot(appMenuModel) : [];
            const expectsMenu=root.activePid===pid && root.menuService!=="" && root.menuPath!=="";
            if (!allowFallback && expectsMenu && (!appMenuModel.menuAvailable || rows.length===0)) return null;
            return {rows:rows,name:rows.length?"":root.fallbackName,fullscreen:graphiteEdge.fullscreen,pid:pid};
        }
        function visualKey(next) { return JSON.stringify([next.rows,next.name,next.fullscreen]); }
        function queueContent() { if(ready)layoutSettle.restart(); }
        function commit(next,animate) {
            animateCommit=animate;
            if(animate){
                outgoingRows=displayedRows;outgoingName=displayedName;outgoingFullscreen=displayedFullscreen;
                startWidth=visualWidth;
                Native.PanelTools.beginMenuMorph(menuPresentation);
                blend=0;
            }
            displayedRows=next.rows;displayedName=next.name;displayedFullscreen=next.fullscreen;
            displayedPid=next.pid;displayedKey=visualKey(next);
            phase="prepare";geometrySettle.restart();
        }
        function finishWithoutMotion() {
            reserveDeadline.stop();
            measuredWidth=endWidth;visualWidth=endWidth;blend=1;
            Native.PanelTools.finishMenuMorph(menuPresentation,endWidth);
            outgoingRows=[];outgoingName="";phase="idle";queueContent();
        }
        function startMorphIfReady() {
            if(phase==="reserve" && Native.PanelTools.menuSurfaceReady(menuPresentation,measuredWidth)){
                reserveDeadline.stop();phase="morph";crossfade.start();
            }
        }
        function transition() {
            // Update a not-yet-visible target in place; rapid focus changes must
            // not first show the app that the user has already left.
            if(phase==="prepare" || phase==="reserve"){
                const pending=desiredContent(false);
                if(pending && visualKey(pending)!==displayedKey){
                    displayedRows=pending.rows;displayedName=pending.name;
                    displayedFullscreen=pending.fullscreen;displayedPid=pending.pid;
                    displayedKey=visualKey(pending);phase="prepare";geometrySettle.restart();
                }
                return;
            }
            // Finish a running crossfade rather than restarting it on model notifications.
            if(phase!=="idle" || Plasmoid.currentIndex>=0)return;
            const next=desiredContent(waitSince!==0 && Date.now()-waitSince>=350);
            if(!next){
                if(waitSince===0)waitSince=Date.now();
                importDeadline.restart();return;
            }
            waitSince=0;importDeadline.stop();
            if(visualKey(next)===displayedKey){displayedPid=next.pid;return;}
            const hidden=Native.PanelTools.contentIsHidden(root);
            if((graphiteEdge.suppressed || (graphiteEdge.fullscreen&&!graphiteEdge.revealed))&&!hidden)return;
            commit(next,ready&&!hidden&&!graphiteEdge.suppressed);
        }
        Connections {
            target: root
            function onFallbackNameChanged(){menuPresentation.queueContent();}
            function onMenuMatchesWindowChanged(){menuPresentation.queueContent();}
            function onActivePidChanged(){menuPresentation.waitSince=0;menuPresentation.queueContent();}
            function onMenuServiceChanged(){menuPresentation.queueContent();}
            function onMenuPathChanged(){menuPresentation.queueContent();}
        }
        Connections { target: graphiteEdge; function onCurrentChanged(){menuPresentation.queueContent();} }
        Connections { target: Native.PanelTools; function onContentHidden(){menuPresentation.queueContent();} function onMenuViewportChanged(){menuPresentation.startMorphIfReady();} }
        Connections {
            target: appMenuModel
            function onVisibleChanged(){menuPresentation.queueContent();}
            function onMenuAvailableChanged(){menuPresentation.queueContent();}
            function onDataChanged(){menuPresentation.queueContent();}
            function onModelReset(){menuPresentation.queueContent();}
            function onRowsInserted(){menuPresentation.queueContent();}
            function onRowsRemoved(){menuPresentation.queueContent();}
        }
        // A constrained or reconfigured surface may never reach the requested
        // width. Never leave all menu buttons disabled awaiting that geometry.
        Timer { id: reserveDeadline; interval: 240; onTriggered: if(menuPresentation.phase==="reserve")menuPresentation.finishWithoutMotion(); }
        Timer { id: layoutSettle; interval: 60; onTriggered: menuPresentation.transition() }
        Timer { id: importDeadline; interval: 360; onTriggered: menuPresentation.transition() }
        Timer {
            id: geometrySettle; interval: 16
            onTriggered: {
                liveContents.ensurePolished();
                menuPresentation.endWidth=menuPresentation.naturalWidth;
                if(menuPresentation.animateCommit){
                    // Reserve the larger surface once. Only scene geometry moves per frame.
                    menuPresentation.measuredWidth=Math.max(menuPresentation.startWidth,menuPresentation.endWidth);
                    menuPresentation.phase="reserve";reserveDeadline.restart();
                    Qt.callLater(function(){menuPresentation.startMorphIfReady();});
                }else{
                    menuPresentation.measuredWidth=menuPresentation.endWidth;
                    menuPresentation.visualWidth=menuPresentation.endWidth;
                    menuPresentation.blend=1;menuPresentation.phase="idle";
                }
            }
        }
        NumberAnimation {
            id: crossfade; target: menuPresentation; property: "blend"
            from: 0; to: 1; duration: 140; easing.type: Easing.OutCubic
            onStarted: menuPresentation.transitionCount++
            onFinished: {
                menuPresentation.measuredWidth=menuPresentation.endWidth;
                Native.PanelTools.finishMenuMorph(menuPresentation,menuPresentation.endWidth);
                menuPresentation.outgoingRows=[];menuPresentation.outgoingName="";
                menuPresentation.phase="idle";menuPresentation.queueContent();
            }
        }
        Component.onCompleted: { commit(desiredContent(true),false);ready=true;Native.PanelTools.setContentAlpha(root,1); }
        Component.onDestruction: Native.PanelTools.finishMenuMorph(menuPresentation,measuredWidth)
        Plasmoid.status: graphiteEdge.left || (appMenuModel.menuAvailable && Plasmoid.currentIndex>-1)
            ? PlasmaCore.Types.NeedsAttentionStatus : PlasmaCore.Types.ActiveStatus
        Binding { target: Plasmoid; property: "buttonGrid"; value: liveContents; restoreMode: Binding.RestoreNone }
        Connections {
            target: Plasmoid
            function onRequestActivateIndex(index:int){liveContents.activate(index);}
            function onActivated(){liveContents.activate(0);}
            function onCurrentIndexChanged(){menuPresentation.queueContent();}
        }
        Item {
        id: contentClip
        width: menuPresentation.visualWidth
        height: parent.height
        clip: true
        MenuContents {
            id: liveContents
            objectName: "graphite-menu-incoming"
            entries: menuPresentation.displayedRows
            applicationName: menuPresentation.displayedName
            fullscreen: menuPresentation.displayedFullscreen
            vertical: root.vertical
            currentIndex: Plasmoid.currentIndex
            opacity: menuPresentation.blend
            controlsInteractive: menuPresentation.phase==="idle"
            interactive: menuPresentation.phase==="idle" && root.menuMatchesWindow && menuPresentation.displayedPid===root.activePid
            onMenuActivated: (button,index)=>Plasmoid.trigger(button,index)
            onControlActivated: action=>graphiteEdge.action(action)
        }
        MenuContents {
            id: outgoingContents
            objectName: "graphite-menu-outgoing"
            visible: menuPresentation.phase!=="idle" && menuPresentation.animateCommit
            entries: menuPresentation.outgoingRows
            applicationName: menuPresentation.outgoingName
            fullscreen: menuPresentation.outgoingFullscreen
            vertical: root.vertical
            opacity: 1-menuPresentation.blend
        }
        }
    }

    AppMenuModel {
        id: appMenuModel
        // A native QMenu temporarily owns keyboard focus. Keep its imported
        // actions alive until it closes; losing the application task here must
        // not clear the menu the user is currently navigating.
        containmentStatus: Plasmoid.currentIndex >= 0
            ? PlasmaCore.Types.AcceptingInputStatus : Plasmoid.containment.status
        screenGeometry: root.screenGeometry
        allScreens: false
        onRequestActivateIndex: Plasmoid.requestActivateIndex(index)
        Component.onCompleted: {
            Plasmoid.model = appMenuModel;
        }
    }
}
