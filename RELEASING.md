# Releasing

How to cut a release of this Flatpak package. For where releases can be
*published* — GitHub, a hosted Flatpak remote, Flathub, Bazaar — see
[DISTRIBUTION.md](DISTRIBUTION.md).

## Prerequisite: a reproducible build

**Nothing here can be automated until the build works from a clean checkout.**

`com.anthropic.Claude.yml` and `simple-build.sh` both read the application
files from `../claude-desktop/build/`, a directory outside this repository:

```yaml
sources:
  - type: dir
    path: ../claude-desktop/build/electron-app   # not in this repo
  - type: file
    path: ../claude-desktop/build/claude_6_256x256x32.png
```

So only a machine that already has that directory can build the package. CI
cannot, and neither can anyone who clones the repo. Until this is fixed:

- the release workflow prepares the GitHub Release but cannot build the bundle;
- you build locally with `./simple-build.sh` and attach the bundle by hand.

Fixing it means having the manifest fetch its inputs from a pinned URL with a
checksum. Since June 2026 Anthropic publishes an official Linux `.deb`, which is
the sensible input:

```
https://downloads.claude.ai/claude-desktop/apt/stable/
```

Two options, both standard Flatpak practice:

1. **`extra-data`** — the `.deb` is downloaded on the user's machine at install
   time. Nothing proprietary is redistributed by you. This is how Spotify, Zoom
   and Discord are packaged, and it is the only option acceptable to Flathub.
2. **`archive`/`file` source with a pinned `sha256`** — simpler, but it means
   your build host downloads and repackages Anthropic's binary. Fine for a
   private build; see the licensing note in DISTRIBUTION.md before publishing.

Either way add [`x-checker-data`](https://github.com/flathub/flatpak-external-data-checker)
so the pinned version can be bumped automatically when Anthropic ships an update.

Also note the manifest is currently out of sync with the build script: the
manifest has a `nodejs` module and launches `electron` directly, while
`simple-build.sh` bundles Electron 32.2.0 and launches it through
`zypak-wrapper`. `simple-build.sh` is the path that actually produces a working
package. Reconcile them as part of the same change.

## Versioning

Two version numbers are in play — keep them distinct:

| Version | Meaning | Where it lives |
|---|---|---|
| Packaging version | This repo's releases (e.g. `1.1.0`) | git tag, `CHANGELOG.md`, metainfo `<release version>` |
| Claude Desktop version | The app being packaged (e.g. `0.14.10`) | named in the metainfo release description |

Tags are `vX.Y.Z`. Bump the **minor** version for packaging changes and new
Claude Desktop versions, the **patch** version for fixes to the packaging
itself.

## Release checklist

1. **Update `CHANGELOG.md`** — move `[Unreleased]` items under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading. The heading format is parsed by
   `scripts/extract-release-notes.sh`, so keep it exact.

2. **Add a `<release>` entry** to `com.anthropic.Claude.metainfo.xml`, newest
   first. This is what GNOME Software and Bazaar show as "What's New".

3. **Verify consistency:**

   ```bash
   ./scripts/check-version.sh X.Y.Z
   ./scripts/extract-release-notes.sh X.Y.Z
   appstreamcli validate --explain com.anthropic.Claude.metainfo.xml
   ```

4. **Build and smoke-test the bundle:**

   ```bash
   ./simple-build.sh
   flatpak install --user --reinstall claude-desktop.flatpak
   flatpak run com.anthropic.Claude
   ```

   Check it launches, signs in, has working window controls on both X11 and
   Wayland, and that Desktop Commander / MCP servers still work.

5. **Commit, tag and push:**

   ```bash
   git commit -am "Release vX.Y.Z"
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push -u origin main
   git push origin vX.Y.Z
   ```

6. **Publish.** The tag triggers `.github/workflows/release.yml`, which
   validates metadata and opens a **draft** GitHub Release with notes from the
   changelog. Attach the bundle and publish:

   ```bash
   gh release upload vX.Y.Z claude-desktop.flatpak
   gh release edit vX.Y.Z --draft=false
   ```

7. **Update the Flatpak remote**, if you host one — see
   [DISTRIBUTION.md](DISTRIBUTION.md#2-a-hosted-flatpak-remote). Users who
   installed from the remote get the update via `flatpak update`; users who
   installed a bundle do not, and have to download the new bundle.

## Rolling back

A published Flatpak remote can be reverted by re-exporting the previous commit:

```bash
flatpak build-commit-from --src-ref=app/com.anthropic.Claude/x86_64/stable \
    repo repo   # then re-run build-update-repo and redeploy
```

For a bundle-only release, mark the GitHub Release as a pre-release or delete
the asset — there is no update channel to roll back.
