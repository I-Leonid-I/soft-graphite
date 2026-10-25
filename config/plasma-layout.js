// Soft Graphite panel layout: on every screen a bottom dock and two top capsules
// (left: launcher + app menu, right: tray + keyboard layout + clock).
//
// REMOVES ALL EXISTING PANELS. Run once, from a terminal inside the Plasma session:
//   qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat config/plasma-layout.js)"
// Afterwards check in panel Edit Mode that each panel is floating, "Fit content"
// and "Windows go below" (see AGENTS.md, step "Panels").

panels().forEach(function (p) { p.remove(); });

var launchers = "applications:org.kde.dolphin.desktop,applications:org.kde.konsole.desktop,applications:systemsettings.desktop";

function capsule(screen, location, alignment, thickness) {
    var p = new Panel("org.kde.panel");
    p.screen = screen;
    p.location = location;
    p.height = thickness;
    p.alignment = alignment;
    p.lengthMode = "fit";
    p.floating = true;
    p.hiding = "windowsgobelow";
    p.opacity = "opaque";
    if (location === "top")
        p.offset = 2;
    return p;
}

for (var s = 0; s < screenCount; ++s) {
    // Bottom dock: 60 px, 48 px icons, pinned apps are shared by all docks.
    var bottom = capsule(s, "bottom", "center", 60);
    var dock = bottom.addWidget("org.leonid.softgraphite.dock");
    dock.currentConfigGroup = ["General"];
    dock.writeConfig("launchers", launchers);
    dock.writeConfig("showOnlyCurrentScreen", "true");
    dock.writeConfig("highlightWindows", "false");
    dock.writeConfig("indicateAudioStreams", "false");
    dock.writeConfig("taskHoverEffect", "false");
    dock.writeConfig("unhideOnAttention", "false");
    dock.writeConfig("fill", "true");

    // Top-left capsule: launcher + application name and global menu.
    var left = capsule(s, "top", "left", 32);
    var kickoff = left.addWidget("org.kde.plasma.kickoff");
    kickoff.currentConfigGroup = ["General"];
    kickoff.writeConfig("icon", "view-grid");
    kickoff.writeConfig("alphaSort", "true");
    left.addWidget("org.leonid.softgraphite.appmenu");

    // Top-right capsule: tray, keyboard layout, date and time.
    var right = capsule(s, "top", "right", 32);
    // Tray: shown items (network, volume, battery, notifications) are set in its settings.
    right.addWidget("org.leonid.softgraphite.tray");
    right.addWidget("org.leonid.softgraphite.keyboard");
    var clock = right.addWidget("org.leonid.softgraphite.clock");
    clock.currentConfigGroup = ["Appearance"];
    clock.writeConfig("autoFontAndSize", "false");
    clock.writeConfig("fontFamily", "Fira Sans");
    clock.writeConfig("fontSize", "10");
    clock.writeConfig("fontWeight", "400");
    clock.writeConfig("showDate", "true");
    clock.writeConfig("dateFormat", "custom");
    clock.writeConfig("customDateFormat", "ddd, d MMM");
    clock.writeConfig("dateDisplayFormat", "1");
    clock.writeConfig("showSeconds", "Never");
}
