# Sandbox Posture

Arklike will start as an **unsandboxed Developer ID / local macOS app**.

Reasoning:

- The planned Safari automation relies on Apple Events, `System Events`, and Accessibility/AX UI scripting.
- Safari profile switching is not exposed through a stable public API, so the app needs room to use menu automation and focused-window tracking.
- Keeping the first implementation unsandboxed reduces iteration risk while proving `Cmd+T`, `Cmd+S`, profile switching, and Traffic Control behavior.

The app still includes an Apple Events entitlement file so the project documents the automation requirement and can be revisited if a sandboxed distribution path is evaluated later.
