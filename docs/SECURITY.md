# Sandbox posture

## What this package does

**zypak, not `--no-sandbox`.** Electron's SUID sandbox helper cannot work inside
a flatpak: OSTree strips setuid, and the user-namespace fallback that upstream's
postinst enables through an AppArmor profile is blocked because Flatpak forbids
nested user namespaces. The common workaround in repackagers is to pass
`--no-sandbox`, which does not disable "a" sandbox. It removes renderer and GPU
process isolation entirely. From then on, any compromised web content inherits
*everything the flatpak holds*: the network share, every `--filesystem=` grant,
every `--talk-name=`. For an app that stores an account credential and reads
source code, that collapses two boundaries at once.

`org.electronjs.Electron2.BaseApp` ships [zypak](https://github.com/refi64/zypak),
which intercepts Chromium's sandbox calls and runs each renderer in a nested
flatpak sub-sandbox instead. Upstream does ship a `chrome-sandbox` helper;
`apply_extra` removes it at install time, since zypak takes over before
Chromium looks for one and an unprivileged copy would only ever produce the
"helper found but not configured correctly" fatal exit. `apply_extra` refuses
to install at all if `zypak-wrapper` is missing, because without it nothing
is isolated. `--require-version=1.8.2` is in `finish-args` because zypak's
faster spawn strategy needs `expose-pids`.

**`--persist=.` is not a widening.** The Code tab is Claude Code, which writes
`~/.claude/` and `~/.claude.json` straight into `$HOME` and ignores the XDG
directories. Sandbox `$HOME` is a throwaway tmpfs, so without persistence every
launch starts from nothing. `--persist` takes directories only, and a top-level
dotfile can be kept only by persisting the whole home. What it does is bind the
sandbox's `$HOME` to `~/.var/app/io.github.rulin132.ClaudeDesktop/`, which is
already the app's own data directory. No host path becomes visible. Steam on
Flathub uses the same pattern for the same reason.

**Sealed permissions.** Deliberately absent from `finish-args`:

| Not granted | Why |
|---|---|
| `--filesystem=host` / `=home` | the app sees no user files until you say so |
| `--talk-name=org.freedesktop.Flatpak` | this permits `flatpak-spawn --host`, i.e. arbitrary command execution outside the sandbox. Flathub treats it as an exception-requiring rule. VS Code holds it, plus `--filesystem=host` and `--allow=devel`, which is why a flatpak'd VS Code is not meaningfully confined |
| `--device=all` / `--device=kvm` | `--device=dri` covers GPU without handing over every USB device. `kvm` would be the first step toward Cowork's VM, and the runtime ships none of the rest (qemu, OVMF, virtiofsd), so granting it would widen the sandbox for nothing |
| `--socket=x11` | `--socket=fallback-x11` gives X11 only when there is no Wayland session. XWayland is a shared server: a client with X11 access can observe other X11 clients' windows and input |

Grant the minimum you need, per directory:

```sh
flatpak override --user --filesystem=~/code/thisproject io.github.rulin132.ClaudeDesktop
flatpak override --user --show io.github.rulin132.ClaudeDesktop     # review
flatpak override --user --reset io.github.rulin132.ClaudeDesktop    # start over
```

The trade is real: with a sealed sandbox, Claude Code can only run commands
against the tools inside the runtime, not your host toolchain, and the runtime
has no git. If you widen it to `--talk-name=org.freedesktop.Flatpak` to get host
execution back, you have opted out of the sandbox. Do that knowingly, not by
copying a snippet.

## Chrome native messaging

Upstream ships `resources/chrome-native-host` for the Claude in Chrome
extension. It is unsupported in this Flatpak package, including when Chrome
itself runs as a Flatpak. The extension may report that the desktop app is not
installed. That does not mean broader Flatpak permissions are needed.

Making it work would require a host-side native-messaging executable that the
sandboxed app can reach. Any such executable stored in data the Flatpak can
write is one the sandboxed app could modify and have Chrome later run outside
the sandbox ([CWE-732](https://cwe.mitre.org/data/definitions/732.html),
incorrect permission assignment for a critical resource). There is no supported
permission workaround, including a temporary one; a temporary filesystem grant
does not protect a persistent host wrapper when the Flatpak can modify it
later. Any future integration needs its own assessment, with the host-executed
code and its configuration kept outside Flatpak-writable storage, including
writable parent directories and symlink targets.

## What this package does not do

**No network egress filtering.** `--share=network` is all-or-nothing; flatpak
has no destination-level control and the request for it
([flatpak#3054](https://github.com/flatpak/flatpak/issues/3054)) was closed.
Network access additionally exposes host services listening on abstract unix
sockets. If you need default-deny egress you must build it outside flatpak: a
dedicated network namespace around the launch, or nftables matching the app's
`app-flatpak-*.scope` cgroup.

**Not a trust boundary for other people's code.** Flatpak 1.17.4 (Apr 2026)
fixed a complete sandbox escape to host code execution; 1.19.0 (11 Aug 2026)
fixed ten more, including a path traversal in *extra-data extraction*
specifically. The flatpak boundary is a good usability and blast-radius
boundary. It is not where you should place a credential or client-data
boundary. For work under a client engagement, run the agent in a container cell
with its own credentials and a default-deny egress policy, and keep this
flatpak for personal use.

**Every install reaches Anthropic's CDN directly.** `extra-data` is fetched
per-machine at install and repair time; it cannot be baked into an OS image. On
a fleet with an egress policy, mirror the `.deb` to an internal artifact store
and repoint `url:`, which also gives you a stable hash.

## Supply chain

- The vendor payload is pinned by `sha256` + `size` from Anthropic's signed
  apt index and verified by flatpak before `apply_extra` runs. A rotated
  artifact fails the install rather than installing unknown bytes. The URLs
  are versioned pool paths, so the bytes behind a pin cannot change.
- The repo is GPG-signed. Signing is not cosmetic here: flatpak refuses
  system-wide installs of extra-data apps from sources that are not
  gpg-verified.
- `apply_extra` fails closed on unexpected layout instead of proceeding.
- No Anthropic executable code is rebuilt, patched into a binary artifact, or
  re-hosted. The one exception is artwork: `build-aux/icons/` holds six PNGs
  from upstream's `.deb`, committed because AppStream metadata and icons must
  exist at build time while the payload only arrives at install time.
  Regenerate them with `make icons`.
- `scripts/apt-index.sh` treats the apt index as untrusted input: version,
  filename, size and checksum are each validated against the grammar that
  field needs before they become a filename, a URL, a git tag or an Actions
  output.

## Reporting

Packaging issues: open an issue here. Bugs in the Claude application itself go
to Anthropic. Reproduce them with the official `.deb` first, since this
packaging does change the process sandbox and the filesystem view.
