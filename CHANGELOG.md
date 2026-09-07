# Changelog

All notable changes to the Claude Desktop Flatpak project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2024-11-02

### Added
- Proper Wayland window decorations for native minimize/maximize/close buttons
- Window dragging functionality
- Support for both X11 and Wayland display servers
- Bundled Electron v32.2.0 for full self-containment

### Changed
- Updated launcher script to use Wayland-native window decorations
- Switched to Electron Ozone platform with Wayland support
- Improved window manager integration

### Fixed
- Missing window controls (minimize/maximize/close buttons)
- Unable to drag/move window
- Window decoration rendering issues on Wayland
- SUID sandbox configuration errors

## [1.0.0] - 2024-11-02

### Added
- Initial Flatpak package for Claude Desktop v0.14.10
- Simple build script that doesn't require flatpak-builder
- Bundled Electron to avoid runtime dependencies
- Full home directory access for Desktop Commander
- Network access for Claude API communication
- GPU acceleration support
- Audio support
- Desktop notifications integration
- File picker integration
- Proper sandboxing with zypak-wrapper

### Features
- Universal Linux distribution support
- Works on immutable systems (Silverblue, Bazzite, etc.)
- Desktop Commander fully functional
- MCP server support
- Configuration stored in ~/.config/claude/

### Technical Details
- Runtime: org.freedesktop.Platform 24.08
- Base: org.electronjs.Electron2.BaseApp 24.08
- Electron Version: 32.2.0
- Claude Desktop Version: 0.14.10

### Security
- Flatpak sandboxing
- zypak-wrapper for Electron sandbox handling
- Controlled filesystem access
- D-Bus mediation for system integration

## [Unreleased]

### Added
- `RELEASING.md` documenting the release process and version scheme
- `DISTRIBUTION.md` covering GitHub Releases, hosted Flatpak remotes, and the
  requirements for Flathub and Bazaar
- `scripts/check-version.sh` to verify the tag, changelog and metainfo agree
- `scripts/extract-release-notes.sh` to generate release notes from this file
- CI workflow validating the AppStream metainfo, desktop entry and manifest
- Tag-driven release workflow that opens a draft GitHub Release
- `.flatpakrepo` template for hosting a Flatpak remote

### Changed
- Metainfo release entries now track packaging versions and match the changelog
- Metainfo uses the current AppStream `<developer>` element and gains
  bugtracker and VCS URLs

### Planned
- Reproducible build from Anthropic's official Linux `.deb` (blocks CI builds)
- Screenshots in the AppStream metadata (required by software centres)
- Hosted Flatpak remote for `flatpak update` support
- Version update automation via flatpak-external-data-checker

---

## Version Numbering

- **Major version** (X.0.0): Breaking changes or major feature additions
- **Minor version** (0.X.0): New features, improvements, or significant fixes
- **Patch version** (0.0.X): Bug fixes and minor improvements

## Notes

- This packaging tracks Claude Desktop's official releases
- Electron version may be updated independently for security fixes
- Runtime versions follow Flatpak's support lifecycle
