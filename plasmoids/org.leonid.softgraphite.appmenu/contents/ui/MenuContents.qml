/* SPDX-License-Identifier: GPL-2.0-or-later */
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.private.keyboardindicator as KeyboardIndicator
import org.kde.kirigami as Kirigami
GridLayout {
    id: contents
    property var entries: []
    property string applicationName: ""
    property bool fullscreen: false
    property bool interactive: false
    property bool controlsInteractive: false
    property bool vertical: false
    property int currentIndex: -1
    signal menuActivated(Item button, int index)
    signal controlActivated(string action)
    function activate(index) { const button=buttonRepeater.itemAt(index); if(button&&button.enabled)button.activated(); }
    width: implicitWidth
    height: parent.height
    flow: vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    rowSpacing: 0
    columnSpacing: 0
    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
        RowLayout {
            visible: contents.fullscreen
            spacing: 2
            Layout.leftMargin: 3
            Layout.rightMargin: 7
            Repeater {
                model: [ {action: "close", label: "Закрыть окно"}, {action: "restore", label: "Вернуть размер"}, {action: "minimize", label: "Свернуть окно"} ]
                delegate: PlasmaComponents3.ToolButton {
                    required property var modelData
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    text: modelData.label
                    Accessible.name: text
                    background: Rectangle { radius: 7; color: parent.down ? (Kirigami.Theme.backgroundColor.r > 0.5 ? "#bbcbdc" : "#556273") : parent.hovered ? (Kirigami.Theme.backgroundColor.r > 0.5 ? "#c8d3e0" : "#485363") : "transparent" }
                    contentItem: Canvas {
                        property color graphiteThemeColor: Kirigami.Theme.textColor
                        onGraphiteThemeColorChanged: requestPaint()
                        onPaint: {
                            var c=getContext("2d");c.reset();c.strokeStyle=(Kirigami.Theme.backgroundColor.r > 0.5 ? "#283342" : "#e5e8ed");c.lineWidth=1.3;c.lineCap="round";
                            var x=width/2,y=height/2;c.beginPath();
                            if (modelData.action==="close") {c.moveTo(x-3.5,y-3.5);c.lineTo(x+3.5,y+3.5);c.moveTo(x+3.5,y-3.5);c.lineTo(x-3.5,y+3.5);}
                            else if(modelData.action==="minimize"){c.moveTo(x-4,y+2);c.lineTo(x+4,y+2);}
                            else {c.rect(x-4,y-2,6,6);c.moveTo(x-1,y-4);c.lineTo(x+4,y-4);c.lineTo(x+4,y+1);}
                            c.stroke();
                        }
                    }
                    enabled: contents.controlsInteractive
                    onClicked: contents.controlActivated(modelData.action)
                }
            }
        }

        PlasmaComponents3.Label {
            id: noMenuPlaceholder
            visible: buttonRepeater.count === 0
            text: contents.applicationName
            color: (Kirigami.Theme.backgroundColor.r > 0.5 ? "#283342" : "#e5e8ed")
            leftPadding: 6
            rightPadding: 10
            verticalAlignment: Text.AlignVCenter
            font.family: "Fira Sans"
            font.pixelSize: 13
            font.weight: Font.Normal
            Layout.fillWidth: contents.vertical
            Layout.fillHeight: !contents.vertical
        }

        Repeater {
            id: buttonRepeater
            model: contents.entries

            GraphiteMenuDelegate {
                id: menuDelegate
                required property int index
                required property var modelData
                readonly property int buttonIndex: index

                Layout.fillWidth: contents.vertical
                Layout.fillHeight: !contents.vertical
                text: modelData.text
                enabled: contents.interactive
                Kirigami.MnemonicData.active: altState.pressed

                down: contents.currentIndex === index
                visible: text !== "" && modelData.visible

                menuIsOpen: contents.currentIndex !== -1
                onActivated: if (enabled) contents.menuActivated(this,index)

                // So we can show mnemonic underlines only while Alt is pressed
                KeyboardIndicator.KeyState {
                    id: altState
                    key: Qt.Key_Alt
                }
            }
        }

}
