import AppKit
import SwiftUI

@MainActor
final class ToastHUD {
    static let shared = ToastHUD()

    private let toastSize = NSSize(width: 154, height: 44)

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    private struct WebViewportCandidate {
        let frame: NSRect
        let depth: Int
    }

    func showURLCopied() {
        show(message: "Copied URL")
    }

    func show(message: String) {
        dismissWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentViewController = NSHostingController(rootView: ToastView(message: message)
            .frame(width: toastSize.width, height: toastSize.height))
        panel.setContentSize(toastSize)
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
            contentRect: NSRect(origin: .zero, size: toastSize),
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
        let webpageFrame = activeSafariWebPageFrameInAppKitCoordinates()
        let frame = webpageFrame
            ?? activeSafariWindowFrameInAppKitCoordinates()
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
        guard let frame else { return }

        let horizontalInset: CGFloat = webpageFrame == nil ? 280 : 28
        let topInset: CGFloat = webpageFrame == nil ? 78 : 24
        let edgeInset: CGFloat = 12
        let leftAnchoredX = frame.minX + horizontalInset
        let origin = NSPoint(
            x: max(frame.minX + edgeInset, min(leftAnchoredX, frame.maxX - panel.frame.width - edgeInset)),
            y: max(frame.minY + edgeInset, frame.maxY - panel.frame.height - topInset)
        )
        panel.setFrameOrigin(origin)
    }

    private func activeSafariWindowFrameInAppKitCoordinates() -> NSRect? {
        guard let window = activeSafariWindowElement() else { return nil }
        return frameInAppKitCoordinates(for: window)
    }

    private func activeSafariWebPageFrameInAppKitCoordinates() -> NSRect? {
        guard let window = activeSafariWindowElement(),
              let windowFrame = frameInAppKitCoordinates(for: window) else { return nil }

        let candidates = webViewportCandidates(in: window, depth: 0, remainingDepth: 10)
        let pageSizedCandidates = candidates.filter { candidate in
            candidate.frame.width >= windowFrame.width * 0.35
                && candidate.frame.height >= windowFrame.height * 0.35
        }
        let usableCandidates = pageSizedCandidates.isEmpty ? candidates : pageSizedCandidates

        return usableCandidates.sorted { lhs, rhs in
            let leftDelta = abs(lhs.frame.minX - rhs.frame.minX)
            if leftDelta > 8 { return lhs.frame.minX < rhs.frame.minX }
            if lhs.depth != rhs.depth { return lhs.depth < rhs.depth }
            return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
        }.first?.frame
    }

    private func activeSafariWindowElement() -> AXUIElement? {
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: FrontmostSafariMonitor.safariBundleIdentifier).first else { return nil }
        let appElement = AXUIElementCreateApplication(safari.processIdentifier)

        if let focused = axWindowAttribute(kAXFocusedWindowAttribute, from: appElement) {
            return focused
        }

        if let main = axWindowAttribute(kAXMainWindowAttribute, from: appElement) {
            return main
        }

        let snapshot = FrontmostSafariMonitor.shared.snapshot.activeWindow
        let windows = axWindows(from: appElement)
        if let snapshot,
           let matched = windows.first(where: { window in
               let titleMatches = snapshot.title != nil && axString(kAXTitleAttribute, from: window) == snapshot.title
               let numberMatches = snapshot.accessibilityWindowNumber != nil && axInt("AXWindowNumber", from: window) == snapshot.accessibilityWindowNumber
               return titleMatches || numberMatches
           }) {
            return matched
        }

        return windows.first
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

    private func webViewportCandidates(in element: AXUIElement, depth: Int, remainingDepth: Int) -> [WebViewportCandidate] {
        guard remainingDepth >= 0 else { return [] }

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }

        var candidates: [WebViewportCandidate] = []
        if axString(kAXRoleAttribute, from: element) == "AXScrollArea",
           children.contains(where: { axString(kAXRoleAttribute, from: $0) == "AXWebArea" }),
           let frame = frameInAppKitCoordinates(for: element) {
            candidates.append(WebViewportCandidate(frame: frame, depth: depth))
        }

        candidates.append(contentsOf: children.flatMap { child in
            webViewportCandidates(in: child, depth: depth + 1, remainingDepth: remainingDepth - 1)
        })

        return candidates
    }

    private func frameInAppKitCoordinates(for element: AXUIElement) -> NSRect? {
        if let frame = axFrameAttributeInAppKitCoordinates(for: element) {
            return frame
        }

        return axPositionAndSizeFrameInAppKitCoordinates(for: element)
    }

    private func axFrameAttributeInAppKitCoordinates(for element: AXUIElement) -> NSRect? {
        var frameValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValue) == .success,
              let frameValue else { return nil }
        var quartzRect = CGRect.zero
        guard AXValueGetValue(frameValue as! AXValue, .cgRect, &quartzRect) else { return nil }
        return appKitRectFromQuartzRect(quartzRect)
    }

    private func axPositionAndSizeFrameInAppKitCoordinates(for element: AXUIElement) -> NSRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
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

#if DEBUG
#Preview("Toast") {
    ToastView(message: "Copied URL")
        .padding(40)
        .frame(width: 340, height: 160)
        .background(.gray.opacity(0.16))
}
#endif

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
