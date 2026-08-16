# Distribution

Where a release can be published, in increasing order of effort and gatekeeping.
For how to *cut* a release, see [RELEASING.md](RELEASING.md).

## Read this first

Since **30 June 2026** Anthropic ships an official Claude Desktop for Linux as a
`.deb` from its own apt repository, covering Ubuntu 22.04+ and Debian 12+ on
x86_64 and arm64 ([docs](https://code.claude.com/docs/en/desktop-linux)).

That changes what this project is for. It is no longer "the only way to run
Claude on Linux" — it is a way to run it on distributions Anthropic does not
package for (Fedora, Arch, openSUSE, and immutable systems like Bazzite and
Silverblue), which is still a real gap the official `.deb` does not fill. It
also changes what this package should be built *from*: the official Linux `.deb`
rather than a 2024-era `app.asar` extracted from the Windows build.

It also affects Flathub eligibility — see below.

## 1. GitHub Releases (available today)

The lowest-effort channel and the one the release workflow already supports.
Attach `claude-desktop.flatpak` to the release; users run:

```bash
flatpak install --user claude-desktop.flatpak
```

**Trade-off:** no update channel. `flatpak update` will not find anything, so
every new version means another manual download. Fine for early releases, poor
as a long-term story.

## 2. A hosted Flatpak remote

A real update channel, and the step that makes the package visible in graphical
software centres — including Bazaar — for anyone who adds the remote. A Flatpak
remote is just static files, so GitHub Pages hosts it for free.

**One-time setup — generate a signing key.** Unsigned remotes are a bad idea;
users are trusting you with code that runs on their machine.

```bash
gpg --quick-gen-key "Claude Desktop Flatpak <you@example.com>" default default never
gpg --export --armor <KEY_ID> > key.gpg
```

**On each release:**

```bash
# Build into an ostree repo rather than straight to a bundle
flatpak-builder --repo=repo --force-clean --gpg-sign=<KEY_ID> \
    build-dir com.anthropic.Claude.yml

# Generate the static metadata clients need, and prune old commits
flatpak build-update-repo repo --gpg-sign=<KEY_ID> \
    --generate-static-deltas --prune --prune-depth=3
```

Publish the `repo/` directory to GitHub Pages, alongside a `.flatpakrepo` file
(a template is in `flatpak/claude-desktop.flatpakrepo.in`). Users then add it
once:

```bash
flatpak remote-add --if-not-exists claude-desktop \
    https://rulin132.github.io/claude-desktop-flatpak/claude-desktop.flatpakrepo
flatpak install claude-desktop com.anthropic.Claude
```

After that `flatpak update` works normally, and the app appears in Bazaar, GNOME
Software and KDE Discover for those users.

**Trade-off:** users must find and add the remote — there is no discovery. And
`repo/` grows with every release, so keep `--prune-depth` small; GitHub Pages
has a 1 GB soft limit and an Electron app is ~200 MB per commit.

## 3. Flathub — and therefore Bazaar

### How Bazaar actually works

Bazaar is a GTK4/libadwaita Flatpak app store, the default on Bazzite and
Bluefin. It has **no submission process of its own** — it is a frontend over
Flatpak remotes, and it draws its app listings, icons, descriptions and
screenshots from Flathub's AppStream data.

So there are exactly two ways to appear in Bazaar:

- **Be on Flathub.** This is what "getting into Bazaar" means in practice —
  every user gets you in search, with no extra steps.
- **Have the user add your remote** (section 2). Bazaar will show the app, but
  only for people who already added it.

The **Curated** tab is not a third route. It is configured by the distribution
maintainers through YAML files that Bazaar watches
(`curated-config-paths` in its config), and it references apps by app ID
against Flathub's table. Getting listed there means asking the Bazzite/Universal
Blue maintainers, and only after you are on Flathub.

### What Flathub requires, and where this package stands

| Requirement | Status |
|---|---|
| App ID matching a domain you control | ❌ **Blocker.** `com.anthropic.Claude` requires proving ownership of `anthropic.com` by serving a token at `/.well-known/org.flathub.VerifiedApps.txt`. |
| Redistributable license | ❌ **Blocker.** Flathub permits proprietary apps only when redistribution is permitted. Claude Desktop is covered by Anthropic's Consumer Terms, which do not grant it. |
| Not already distributed by upstream | ⚠️ Anthropic now ships Linux builds itself, which weakens the case for a third-party submission. |
| Screenshots in AppStream metadata | ❌ Missing. Required for display. |
| Reproducible build, no local paths | ❌ Missing. See RELEASING.md. |
| Valid AppStream + desktop entry | ✅ Validated in CI. |

### The realistic paths

**a. Ask Anthropic.** The clean solution to both blockers at once. They own the
app ID and the license; permission (or their own submission, with this repo's
manifest as the starting point) resolves everything. Worth an email given they
have already stated that support for more distributions is coming.

**b. Package it as a downloader, under your own app ID.** Flathub's
`extra-data` mechanism fetches the `.deb` from Anthropic's servers on the user's
machine at install time, so nothing proprietary is redistributed by you or by
Flathub. This is exactly how Spotify, Zoom and Discord are on Flathub. It
requires renaming the app to an ID you control, e.g.
`io.github.rulin132.ClaudeDesktop`.

This still needs Anthropic's blessing to be safe — the app name, icon and
trademark are theirs, and a third-party listing that looks official invites a
takedown. **Do not submit under `com.anthropic.Claude`; that verification will
fail and the submission will be rejected.**

**c. Stay off Flathub.** Publish via GitHub Releases and your own remote
(sections 1 and 2), as the other community Claude packaging projects do —
`aaddrick/claude-desktop-debian` distributes through GitHub Releases plus its
own apt/dnf repos and is not on Flathub. This is the path with no legal
exposure and no gatekeeper, at the cost of discoverability.

**Recommendation:** ship (1) now, add (2) next for a working update channel, and
open a conversation with Anthropic before attempting (3). The licensing blocker
is not something tooling can route around.

## 4. Other channels worth knowing

- **AUR** — Arch users expect a `PKGBUILD`; no gatekeeper, minimal effort.
- **COPR** — Fedora's build service, for an RPM alongside the Flatpak.
- **Universal Blue images** — Bazzite and friends can bake a Flatpak into the
  image, but again only from a remote they trust.

## Regardless of channel

Make the unofficial status unmissable — in the README, the release notes and
the AppStream summary:

> Community package. Not affiliated with, endorsed by, or supported by
> Anthropic. For the official Linux app see
> <https://code.claude.com/docs/en/desktop-linux>.
