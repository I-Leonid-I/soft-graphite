import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC
import org.kde.kirigami as Kirigami
Item {
    id: root
    required property Item toolTip
    implicitWidth: Math.min(340, textRows.implicitWidth) + 12
    implicitHeight: textRows.implicitHeight + 12
    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false
    ColumnLayout {
        id: textRows
        anchors.fill: parent
        anchors.margins: 6
        spacing: 3
        PC.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: 340
            text: root.toolTip.mainText
            textFormat: Text.PlainText
            visible: text.length > 0
            wrapMode: Text.Wrap
            font.family: "Fira Sans"
            font.pixelSize: 13
        }
        PC.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: 340
            text: root.toolTip.subText
            textFormat: root.toolTip.textFormat
            visible: text.length > 0
            wrapMode: Text.Wrap
            maximumLineCount: 8
            elide: Text.ElideRight
            opacity: 0.75
            font.family: "Fira Sans"
            font.pixelSize: 12
        }
    }
}
