#!/bin/sh
# Launcher. Runs zypak so Chromium's renderer/GPU processes stay in nested
# flatpak sub-sandboxes. Never add --no-sandbox here: it would let compromised
# web content inherit every permission this flatpak holds.
set -eu

# Filesystem prefix the launcher inspects. Empty in the shipped launcher;
# tests/test-launcher.sh runs a copy with this one line rewritten to a fake
# root. Deliberately NOT sourced from an env var: an ambient override of a
# path that gets `.`-sourced below would be arbitrary code execution before
# zypak sandboxes anything.
PREFIX=

[ -f "$PREFIX/app/extra/app.env" ] || { echo "claude-desktop: app.env missing, reinstall the flatpak" >&2; exit 1; }
# shellcheck source=/dev/null  # written by apply_extra at install time
. "$PREFIX/app/extra/app.env"

# Flatpak mounts GL/nvidia-* only when the extension matches the host driver,
# so an NVIDIA device node with no such dir means the host driver updated ahead
# of the extension. Chromium then silently falls back to software rendering.
# Also fires on NVIDIA+iGPU hybrids that render fine on Mesa; stderr-only, so
# acceptable until someone needs vendor detection.
if [ -e "$PREFIX/dev/nvidiactl" ]; then
    gl_ok=0
    for d in "$PREFIX"/usr/lib/*/GL/nvidia-*; do
        [ -d "$d" ] && { gl_ok=1; break; }
    done
    [ "$gl_ok" = 1 ] || echo "claude-desktop: NVIDIA GPU present but no matching GL \
extension is mounted; rendering falls back to software. Run 'flatpak update', \
then restart the app." >&2
fi

# Chromium creates its SingletonSocket under TMPDIR. Flatpak cache paths can
# already be long enough on Atomic desktops to exceed the Unix socket limit.
# Keep temporary files session-scoped and close to the short runtime root.
export TMPDIR="${XDG_RUNTIME_DIR:-/tmp}/claude-desktop"
mkdir -p "$TMPDIR"
chmod 700 "$TMPDIR"

# --enable-wayland-ime is what fixes IME input on Fedora/GNOME Wayland.
set -- --ozone-platform-hint=auto --enable-wayland-ime "$@"

# CLAUDE_DESKTOP_DISABLE_GPU=1 renders in software (see docs/SECURITY.md).
# Deliberately not --disable-gpu: that leaves Chromium with no rasteriser and
# opens no window at all. This routes ANGLE at the bundled SwiftShader instead.
[ "${CLAUDE_DESKTOP_DISABLE_GPU:-0}" = "1" ] && set -- --use-angle=swiftshader "$@"

exec zypak-wrapper "$APP_BIN" "$@"
