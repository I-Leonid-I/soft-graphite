import QtQuick
import "panelnative" as Native
import org.kde.plasma.workspace.dbus as DBus
QtObject {
    id: edge
    property Item panelItem
    readonly property bool suppressed: current.capture || false
    onSuppressedChanged: updateLayer()
    function updateLayer() { Native.PanelTools.configure(panelItem, fullscreen, revealed, "right", suppressed); }
    readonly property bool revealed: right
    onRevealedChanged: updateLayer()
    onFullscreenChanged: updateLayer()
    property Connections windowConnection: Connections { target: edge.panelItem; function onWindowChanged() { edge.updateLayer(); } }
    Component.onCompleted: { bus.updateAll(); updateLayer(); }
    property rect screenGeometry
    readonly property var states: { try { return JSON.parse(bus.properties.uiState || "[]"); } catch(e) { return []; } }
    readonly property var current: states.find(s => s.x === screenGeometry.x && s.y === screenGeometry.y) || ({})
    readonly property bool fullscreen: current.full || false
    readonly property bool left: current.left || false
    readonly property bool right: current.right || false
    readonly property bool bottom: current.bottom || false
    readonly property string output: current.name || ""
    property DBus.Properties bus: DBus.Properties {
        service: "org.leonid.SoftGraphite"
        path: "/SoftGraphite"
        iface: "org.leonid.SoftGraphite"
    }
    function action(name) {
        DBus.SessionBus.asyncCall({service: "org.leonid.SoftGraphite", path: "/SoftGraphite", iface: "org.leonid.SoftGraphite", member: "Action", arguments: [output, name]});
    }
}
