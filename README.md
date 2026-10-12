# Claude Desktop Flatpak

Unofficial Flatpak of **Anthropic's official Claude desktop app for Linux**, for
the distributions Anthropic does not ship packages for: Fedora atomic
(Silverblue, Bluefin, Bazzite, Aurora, Kinoite) · openSUSE Aeon/MicroOS · Arch ·
NixOS · Alpine · Gentoo · Steam Deck · basically any immutable host.

On Ubuntu or Debian, use [Anthropic's own `.deb`](https://code.claude.com/docs/en/desktop-linux)
instead. It updates through apt and supports things this package cannot.

Nothing of Anthropic's is redistributed here. The `.deb` is downloaded from
`downloads.claude.ai` on *your* machine at install time (Flatpak `extra-data`)
and unpacked into the sandbox. This repository holds the manifest, scripts and
metadata, and nothing else.

## Install

```sh
flatpak remote-add --user claude-desktop https://rulin132.github.io/claude-desktop-flatpak/claude-desktop.flatpakrepo
flatpak install --user claude-desktop io.github.rulin132.ClaudeDesktop
```

The app starts with **no access to your files.** Grant a directory explicitly,
for example a project you want the Code tab to work in:

```sh
flatpak override --user --filesystem=~/code/thisproject io.github.rulin132.ClaudeDesktop
```

Also available as an OCI image at `ghcr.io/rulin132/claude-desktop-flatpak`:

```sh
flatpak install --user --image docker://ghcr.io/rulin132/claude-desktop-flatpak:latest
```

### Upgrading from the old `com.anthropic.Claude` build

Earlier versions of this repository built a different app id from a 2024
Windows extract (Claude Desktop 0.14.10, the one that nags about newer models).
Flatpak sees that as an unrelated app; it will not update into this one.
Remove it first:

```sh
flatpak uninstall --user --delete-data com.anthropic.Claude
```

## Sandbox

Sealed by default: no `--filesystem=host`, no
`--talk-name=org.freedesktop.Flatpak`. The app cannot read your home directory
or run commands on your host until you grant it.

Renderers stay isolated under zypak rather than `--no-sandbox`. `--no-sandbox`
does not disable "a" sandbox, it removes renderer isolation entirely, so any
compromised web content inherits every permission the flatpak holds.

Review or undo what you have granted:

```sh
flatpak override --user --show io.github.rulin132.ClaudeDesktop
flatpak override --user --reset io.github.rulin132.ClaudeDesktop
```

Read [docs/SECURITY.md](docs/SECURITY.md) before widening it.

## What does not work

| Feature | Status | Why |
|---|---|---|
| Chat, the Code tab | Expected to work | A standard Electron app under zypak. |
| **Cowork** | **Not available** | It drives a qemu VM: the `.deb` Recommends `qemu-system-x86`, `ovmf` and `virtiofsd`. None of that exists in the runtime and `/dev/kvm` is not granted. |
| `git` inside the Code tab | **Missing** | The Freedesktop runtime ships no git, and the sealed sandbox cannot run host commands. Claude Code's git-backed features (diffs, commits, worktrees) are degraded. Building git into the manifest is the planned fix. |
| Computer Use, dictation | Not on Linux | Upstream limitation, not a packaging one. |
| GNOME Shell search provider | Not registered | Its D-Bus name is `com.anthropic.Claude.*`, which this app id cannot own. |
| Claude in Chrome (native messaging host) | Unsupported | Needs a host-side executable that the sandbox could later modify. See docs/SECURITY.md. |
| Quick Entry global hotkey on Wayland | Needs your desktop's GlobalShortcuts portal | Same as upstream. |

**Caveat, stated plainly:** this port was written against the 2.31226.1 `.deb`
layout and has not yet been launched end-to-end on a desktop. CI proves it
builds, installs and unpacks the real payload on both architectures. The first
interactive launch is a maintainer step, listed under "First release" below.

## Maintaining it

Anyone can run this. Fork it and:

```sh
make rename GH_USER=<you>   # do this first, sets the app-id everywhere
make deps                   # runtimes, SDK, Electron BaseApp, linter
make hashes                 # re-pin url/sha256/size from Anthropic's apt index
make icons                  # replace the placeholder icons with the real ones
make install && make run
```

### Repository setup

None of this is optional, and nothing here is created for you.

**Secrets**

- `GPG_PRIVATE_KEY` and `GPG_KEY_ID`. Flatpak refuses system-wide installs of
  an extra-data app from a remote that is not gpg-verified, so publishing
  without these produces a repo nobody can install system-wide.
- `AUTOMATION_TOKEN`, a personal access token with `contents: write` and
  `pull-requests: write`. The nightly update check uses it instead of
  `GITHUB_TOKEN` because GitHub does not start workflow runs for anything
  `GITHUB_TOKEN` does: a PR opened with it arrives with zero checks. The
  workflow fails on the first step with a clear message if this is unset.

**Settings**

- Pages, source: GitHub Actions.
- Make the GHCR package public. A package created by the first push defaults to
  private, so the `docker://ghcr.io/...` install above returns 401 for everyone
  until you change it under Packages, package settings, change visibility.
- Allow auto-merge, under General. Without it the auto-merge step errors out.
- Branch protection on `main` requiring these four checks: `shellcheck`,
  `lint`, `build (x86_64, ubuntu-latest)`, `build (aarch64, ubuntu-24.04-arm)`.

**Labels and variables**

- A label named `automated`. `gh pr create --label` errors when the label does
  not exist, so without it the nightly job opens no PR at all.
- Repository variable `AUTO_UPDATE`. Unset means off, which is how this ships.
  Set it to `on` to let the nightly refresh PR auto-merge once those four
  checks pass, and to let a manifest change on `main` publish a release. Unset
  it to stop the whole pipeline from the GitHub UI in seconds, with no commit
  and nothing to revert.

### First release

1. `make deps`
2. `make icons`. The committed `build-aux/icons/*.png` are solid-colour
   stand-ins so the manifest builds before a `.deb` has been fetched. Do not
   publish with them.
3. `make install && make run`. This is the first interactive launch. Check
   sign-in, chat, the Code tab, the tray icon, and window controls on Wayland.
   If something is wrong, `scripts/inspect-deb.sh` shows the payload layout.
4. Commit the icons. Set the secrets, settings, label and variable above.
5. Tag the version the metainfo already carries, which `release.yml` enforces:
   ```sh
   v=$(sed -n 's/.*<release version="\([^"]*\)".*/\1/p' build-aux/*.metainfo.xml | head -n1)
   git tag -a "v$v" -m "v$v" && git push origin "v$v"
   ```
   Or run `release.yml` from the Actions tab (`workflow_dispatch`); it
   publishes for real either way.
6. After the first run, make the GHCR package public.
7. When you are happy for nightly re-pins to merge and publish unattended, set
   `AUTO_UPDATE` to `on`.

### The nightly refresh

`update-check.yml` runs `scripts/refresh-source.sh` at 04:23 UTC. It reads
Anthropic's `Packages` index for both architectures, refuses to proceed if
they disagree (upstream mid-publish), re-pins the versioned pool URL, sha256
and size, bumps the AppStream release entry, and opens a PR on
`chore/upstream-refresh` labelled `automated`. If the repository has been quiet
for 50 days it also commits to `chore/keepalive`, because GitHub disables
scheduled workflows after 60 days of inactivity.

Old pool files eventually disappear from Anthropic's repository, at which
point installs of a stale pin 404. The nightly job is what keeps that window
short.

## Known issues

If something misbehaves, capture the log first:

```sh
flatpak run io.github.rulin132.ClaudeDesktop 2>&1 | tee /tmp/claude-desktop.log
```

**A blank window is not fixed with `--disable-gpu`.** That leaves Chromium with
no rasteriser and opens no window at all. Use `CLAUDE_DESKTOP_DISABLE_GPU=1`,
which routes ANGLE at the bundled SwiftShader instead:

```sh
CLAUDE_DESKTOP_DISABLE_GPU=1 flatpak run io.github.rulin132.ClaudeDesktop
```

**NVIDIA: "no matching GL extension is mounted".** The host driver updated
ahead of the Flatpak GL extension. `flatpak update` fetches the matching one.

**The `.deb` is large.** 181 MB download, roughly 480 MB installed, per
architecture. Every install and `flatpak repair` fetches it from Anthropic.

## Uninstalling

```sh
flatpak uninstall --user io.github.rulin132.ClaudeDesktop
```

That keeps your data (sign-in, Claude Code state) in
`~/.var/app/io.github.rulin132.ClaudeDesktop`. To remove that as well:

```sh
flatpak uninstall --user --delete-data io.github.rulin132.ClaudeDesktop
```

## Flathub and Bazaar

Bazaar (the Bazzite/Bluefin app store) has no submission process of its own.
It renders Flathub's catalogue, so being on Flathub is what "being in Bazaar"
means. Users who add this remote see the app in Bazaar, GNOME Software and
Discover already; Flathub is about discovery, not function.

This package is built the way Flathub accepts proprietary apps (`extra-data`,
nothing redistributed) and the app id is verifiable through GitHub. Before
submitting, know that: the metainfo still needs screenshots; the `<developer>`
is deliberately the packager, not Anthropic, because a store listing must not
read as if they published it; and a third-party ChatGPT Flatpak submission in
August 2026 was closed within the hour as AI-generated. Read Flathub's current
policy on that, and talk to Anthropic first, since the name and icon are theirs.

## Legal

The `extra-data` source type means the vendor binary is downloaded from
Anthropic by *your* machine at install time. This repository hosts and
redistributes no Anthropic executable code. It does commit six application
icons in `build-aux/icons/`, taken from (or downscaled from) the icons in
upstream's `.deb`, because icons and AppStream metadata must exist at build
time while the payload only arrives at install time. The licence in `LICENSE`
covers the packaging (manifest, scripts, metadata) and grants no rights to
Anthropic software or services. Not affiliated with Anthropic. You need your
own Claude account and must comply with Anthropic's terms.
