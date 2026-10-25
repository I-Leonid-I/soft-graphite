/*
 * SPDX-FileCopyrightText: 2020 Carson Black <uhhadd@gmail.com>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

import QtQuick
import QtQuick.Controls

import org.kde.ksvg as KSvg
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

AbstractButton {
    id: controlRoot

    property bool menuIsOpen: false

    signal activated()

    // QMenu opens on press, so we'll replicate that here
    hoverEnabled: true

    // This will trigger even if hoverEnabled has just became true and the
    // mouse cursor is already hovering.
    //
    // In practice, this never works, at least on X11: when menuIsOpen the
    // hover event would not be delivered. Instead we rely on
    // plasmoid.requestActivateIndex signal to filter
    // QEvent::MouseMove events and tell us when to change the index.
    onHoveredChanged: if (hovered && menuIsOpen) { activated(); }

    // You don't actually have to "close" the menu via click/pressed handlers.
    // Instead, the menu will be closed automatically, as by any
    // other "outside of the menu" click event.
    onPressed: activated()

    enum State {
        Rest,
        Hover,
        Down
    }

    property int menuState: {
        // can't trust hovered state while QMenu is grabbing mouse pointer.
        if (down) {
            return GraphiteMenuDelegate.State.Down;
        } else if (hovered && !menuIsOpen) {
            return GraphiteMenuDelegate.State.Hover;
        }
        return GraphiteMenuDelegate.State.Rest;
    }

    Kirigami.MnemonicData.controlType: Kirigami.MnemonicData.SecondaryControl
    Kirigami.MnemonicData.label: text

    topPadding: 8
    leftPadding: 8
    rightPadding: 8
    bottomPadding: 8

    Accessible.description: i18ndc("plasma_applet_org.kde.plasma.appmenu", "@info:usagetip", "Open a menu")

    background: Rectangle {
        radius: 6
        color: controlRoot.menuState === GraphiteMenuDelegate.State.Down ? (Kirigami.Theme.backgroundColor.r > 0.5 ? "#c8d3e0" : "#485363") : controlRoot.menuState === GraphiteMenuDelegate.State.Hover ? (Kirigami.Theme.backgroundColor.r > 0.5 ? "#ccd7e4" : "#465261") : "transparent"
        // Immediate hover changes prevent a trail when crossing menu entries.
    }

    contentItem: PC3.Label {
        font.family: "Fira Sans"
        font.pixelSize: 13
        font.weight: Font.Normal
        text: controlRoot.Kirigami.MnemonicData.richTextLabel
        textFormat: Text.StyledText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        // The temporary input lock during a dissolve must not dim the text first.
        color: (Kirigami.Theme.backgroundColor.r > 0.5 ? "#283342" : "#e5e8ed")
    }
}
