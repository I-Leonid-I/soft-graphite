#!/bin/sh
# Use the compatible local core only while the original binary and core match.
base="$HOME/.local/share/soft-graphite/native/powerdevil"
if /usr/bin/sha256sum --status -c "$base/system.sha256"; then
    export LD_LIBRARY_PATH="$HOME/.local/lib/soft-graphite/powerdevil-6.7.5${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
else
    echo "Soft Graphite: PowerDevil changed; using the updated system core." >&2
fi
exec /usr/lib/org_kde_powerdevil "$@"
