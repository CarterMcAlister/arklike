# Arklike

Arklike is a native macOS menu-bar app that recreates Arc-style workflows for Safari.

## Install

Install the signed and notarized macOS app from the Homebrew tap:

```sh
brew tap CarterMcAlister/tools
brew install --cask arklike
```

Arklike requires macOS 14 or newer. On first launch, macOS will prompt for the Accessibility and Apple Events permissions needed to automate Safari workflows.

## Goals

- Open a command-palette style URL/search menu while Safari is frontmost.
- Copy the current Safari tab URL with a shortcut.
- Toggle Safari’s native sidebar.
- Switch to numbered Safari profiles.
- Route external links to selected Safari profiles through Traffic Control rules.

## Requirements

- macOS 14 or newer
- Xcode / Apple Swift toolchain
- `mise` for the included project tasks

## Common Commands

```sh
mise run build      # build .build/Debug/Arklike.app
mise run dev        # rebuild and launch the app
mise run run        # launch the existing build
mise run test       # typecheck Swift sources and lint plist files
mise run clean      # remove local build artifacts
```

The project also includes `Scripts/build-run.sh` for direct local builds without opening Xcode.

## Permissions

Arklike relies on native macOS automation rather than a Safari extension. Some features require explicit system permissions:

- Accessibility for Safari-focused shortcut handling, active-window tracking, profile menu automation, and sidebar toggling.
- Apple Events for Safari tab/window automation and URL copying.
- Optional default-browser setup for Traffic Control external link routing.

## Distribution Notes

The MVP is intended for local/developer builds first. See `Docs/Distribution.md` and `Docs/SandboxDecision.md` for the current distribution and sandboxing posture.
