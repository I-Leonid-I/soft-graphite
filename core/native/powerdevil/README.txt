Soft Graphite — responsive external brightness (revision 39)

Upstream: https://github.com/KDE/powerdevil/tree/v6.7.5
Installed base: powerdevil 6.7.5-2.1 (CachyOS).
Only libpowerdevilcore is rebuilt. No files in /usr are replaced.

DDCutilDisplay normally restarts a 1000 ms debounce on every input. This patch
coalesces input for 100 ms without continually postponing the deadline. At most
one transaction per display is in flight. When it completes, only the latest
requested value is scheduled; obsolete values are never queued. Equal values
are skipped. Existing failure retries and backoff intervals are preserved.
All DDC I/O stays on the existing worker thread, not the UI/compositor thread.
No new daemon, idle polling, software dimming, or monitor timing override.

The systemd drop-in invokes launch.sh. It checks SHA-256 of both installed
PowerDevil executable and core before enabling the user-local library directory.
After a package update changes either file, it uses the updated system core.
This avoids retaining an incompatible old core across upgrades, but the shorter
DDC delay will then need a compatible rebuild. No automatic source patching.

Source patch: ddc-responsive.patch (apply to the matching KDE/powerdevil tag).
Build target: powerdevilcore, Release, prefix /usr; Qt/KF from this system.
Build-only ECM/cmake and Plasma Wayland protocol files are user-local.
Native daemon/plugins/translations/policies remain supplied by the distro.

Revert: remove ~/.config/systemd/user/plasma-powerdevil.service.d/50-soft-graphite-ddc.conf,
then systemctl --user daemon-reload && systemctl --user restart plasma-powerdevil.
