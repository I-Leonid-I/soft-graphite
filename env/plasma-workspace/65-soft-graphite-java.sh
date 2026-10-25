#!/bin/sh
# Native Java/JetBrains frame policy (same value as environment.d/65-soft-graphite-java.conf).
# JetBrains launchers already pass --enable-native-access for the Global Menu plugin; adding it
# here would break any Java older than 17 started from the session.
case "${_JAVA_OPTIONS:-}" in
  *"sun.awt.wl.WindowDecorationStyle"*) ;;
  *) export _JAVA_OPTIONS="${_JAVA_OPTIONS:+$_JAVA_OPTIONS }-Dsun.awt.wl.WindowDecorationStyle=server -Dide.linux.hide.native.title=false -Dide.message.dialogs.as.swing.alert.show.title.bar=true" ;;
esac
