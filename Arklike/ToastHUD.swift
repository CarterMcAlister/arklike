import AppKit
import SwiftUI

@MainActor
final class ToastHUD {
    static let shared = ToastHUD()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func showURLCopied() {
        show(message: "URL copied")
    }

    func show(message: String) {
        dismissWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: ToastView(message: message))
        position(panel: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            panel.animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.hide() }
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15, execute: workItem)
    }

    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 136, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        return panel
    }

    private func position(panel: NSPanel) {
        let frame = activeSafariWindowFrameInAppKitCoordinates()
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
        guard let frame else { return }
        let margin: CGFloat = 20
        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - margin,
            y: frame.maxY - panel.frame.height - margin
        )
        panel.setFrameOrigin(origin)
    }

    private func activeSafariWindowFrameInAppKitCoordinates() -> NSRect? {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first else { return nil }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)

        if let focused = axWindowAttribute(kAXFocusedWindowAttribute, from: appElement),
           let frame = frameInAppKitCoordinates(for: focused) {
            return frame
        }

        if let main = axWindowAttribute(kAXMainWindowAttribute, from: appElement),
           let frame = frameInAppKitCoordinates(for: main) {
            return frame
        }

        let snapshot = FrontmostSafariMonitor.shared.snapshot.activeWindow
        let windows = axWindows(from: appElement)
        if let snapshot,
           let matched = windows.first(where: { window in
               let titleMatches = snapshot.title != nil && axString(kAXTitleAttribute, from: window) == snapshot.title
               let numberMatches = snapshot.accessibilityWindowNumber != nil && axInt("AXWindowNumber", from: window) == snapshot.accessibilityWindowNumber
               return titleMatches || numberMatches
           }),
           let frame = frameInAppKitCoordinates(for: matched) {
            return frame
        }

        if let first = windows.first,
           let frame = frameInAppKitCoordinates(for: first) {
            return frame
        }

        return nil
    }

    private func axWindowAttribute(_ attribute: String, from appElement: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, attribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private func axWindows(from appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return [] }
        return windows
    }

    private func frameInAppKitCoordinates(for window: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var quartzOrigin = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &quartzOrigin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &windowSize) else { return nil }
        return appKitRectFromQuartzRect(CGRect(origin: quartzOrigin, size: windowSize))
    }

    private func appKitRectFromQuartzRect(_ quartzRect: CGRect) -> NSRect? {
        let quartzCenter = CGPoint(x: quartzRect.midX, y: quartzRect.midY)
        for screen in NSScreen.screens {
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { continue }
            let displayBounds = CGDisplayBounds(displayID)
            guard displayBounds.contains(quartzCenter) else { continue }
            let x = screen.frame.minX + (quartzRect.minX - displayBounds.minX)
            let yTop = quartzRect.minY - displayBounds.minY
            let y = screen.frame.maxY - yTop - quartzRect.height
            return NSRect(x: x, y: y, width: quartzRect.width, height: quartzRect.height)
        }
        return nil
    }

    private func axString(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func axInt(_ attribute: String, from element: AXUIElement) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
            Text(message)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(.black.opacity(0.78), in: Capsule())
    }
}
