# Arklike Distribution Notes

## MVP distribution route

Use local developer builds first, then Developer ID notarization for direct distribution once Safari automation has been tested across target macOS/Safari versions.

## Sandbox posture

The MVP remains unsandboxed. Safari Apple Events, Accessibility-driven shortcut capture, System Events menu automation, and default-browser routing are core requirements and should be proven before revisiting App Store constraints.

## First-run onboarding

The first-run experience should guide users through:

1. Accessibility permission for Safari shortcut interception, active-window tracking, profile menu automation, and sidebar toggling.
2. Apple Events permission for Safari tab/window automation and URL copying.
3. Optional default-browser setup for Traffic Control external link routing.
4. Safari profile setup, including manual profile names when discovery fails.

## Future updates

If distributing directly, add Sparkle or an equivalent updater after the MVP is stable.
