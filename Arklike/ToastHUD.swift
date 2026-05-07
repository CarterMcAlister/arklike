import AppKit
import SwiftUI

@MainActor
final class ToastHUD {
    static let shared = ToastHUD()

    private let toastSize = NSSize(width: 154, height: 44)

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

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
        let frame = screenForLastSafariWindow()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
        guard let frame else { return }

        let horizontalInset: CGFloat = 280
        let topInset: CGFloat = 78
        let edgeInset: CGFloat = 12
        let leftAnchoredX = frame.minX + horizontalInset
        let origin = NSPoint(
            x: max(frame.minX + edgeInset, min(leftAnchoredX, frame.maxX - panel.frame.width - edgeInset)),
            y: max(frame.minY + edgeInset, frame.maxY - panel.frame.height - topInset)
        )
        panel.setFrameOrigin(origin)
    }

    private func screenForLastSafariWindow() -> NSScreen? {
        guard let center = FrontmostSafariMonitor.shared.lastActiveWindowForSafariAction()?.center else { return nil }
        return NSScreen.screens.first { $0.frame.contains(center) }
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
