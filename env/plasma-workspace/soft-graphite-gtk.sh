#!/bin/sh
# Load the global-menu bridge before GTK creates widgets.
graphite_gtk="$HOME/.local/share/soft-graphite/appmenu/lib/gtk-3.0"
case ":${GTK_PATH:-}:" in
    *":$graphite_gtk:"*) ;;
    *) export GTK_PATH="$graphite_gtk${GTK_PATH:+:$GTK_PATH}" ;;
esac
case ":${GTK_MODULES:-}:" in
    *":appmenu-gtk-module:"*) ;;
    *) export GTK_MODULES="${GTK_MODULES:+$GTK_MODULES:}appmenu-gtk-module" ;;
esac
unset graphite_gtk
