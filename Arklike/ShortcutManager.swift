import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

@MainActor
final class ShortcutManager: ObservableObject {
    static let shared = ShortcutManager()

    typealias Handler = (ShortcutAction) -> Void

    @Published private(set) var shortcuts: [ShortcutAction: KeyboardShortcut]
    @Published private(set) var conflictMessage: String?
    @Published private(set) var isCarbonHandlerInstalled = false
    @Published private(set) var isEventTapInstalled = false
    @Published private(set) var registeredActions: Set<ShortcutAction> = []

    private let defaults: UserDefaults
    private let defaultsKey = "shortcutBindings.v1"
    private var handler: Handler?
    private var carbonEventHandler: EventHandlerRef?
    private var registeredHotKeys: [ShortcutAction: EventHotKeyRef] = [:]
    private var actionsByHotKeyID: [UInt32: ShortcutAction] = [:]
    private var monitorCancellable: AnyCancellable?
    private var nextHotKeyID: UInt32 = 1
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.shortcuts = Self.loadShortcuts(defaults: defaults, key: defaultsKey)
        self.conflictMessage = Self.conflictMessage(for: shortcuts)
    }

    func start(handler: @escaping Handler) {
        self.handler = handler
        installCarbonEventHandlerIfNeeded()
        installEventTapIfNeeded()
        monitorCancellable = FrontmostSafariMonitor.shared.$snapshot.sink { [weak self] _ in
            Task { @MainActor in
                self?.reconcileRegisteredHotKeys()
            }
        }
        reconcileRegisteredHotKeys()
    }

    func stop() {
        unregisterAllHotKeys()
        if let carbonEventHandler { RemoveEventHandler(carbonEventHandler) }
        carbonEventHandler = nil
        isCarbonHandlerInstalled = false
        if let eventTapRunLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        eventTapRunLoopSource = nil
        isEventTapInstalled = false
        monitorCancellable = nil
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func updateShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> Bool {
        var candidate = shortcuts
        candidate[action] = shortcut
        if let conflict = Self.conflictMessage(for: candidate) {
            conflictMessage = conflict
            return false
        }

        shortcuts = candidate
        conflictMessage = nil
        persist()
        reconcileRegisteredHotKeys()
        return true
    }

    func resetShortcut(_ action: ShortcutAction) {
        shortcuts[action] = action.defaultShortcut
        conflictMessage = Self.conflictMessage(for: shortcuts)
        persist()
        reconcileRegisteredHotKeys()
    }

    func resetAllShortcuts() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        conflictMessage = nil
        persist()
        reconcileRegisteredHotKeys()
    }

    func conflictingActions() -> [ShortcutAction] {
        let groups = Dictionary(grouping: shortcuts) { $0.value }
        return groups.values.filter { $0.count > 1 }.flatMap { $0.map(\.key) }.sorted { $0.title < $1.title }
    }

    fileprivate func handleCarbonHotKey(id: UInt32) -> OSStatus {
        guard let action = actionsByHotKeyID[id] else { return noErr }
        guard isActionEnabled(action) else {
            reconcileRegisteredHotKeys()
            return noErr
        }
        handler?(action)
        return noErr
    }

    fileprivate func handleEventTap(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let action = actionMatching(event: event), isActionEnabled(action) else {
            return Unmanaged.passUnretained(event)
        }
        handler?(action)
        return nil
    }

    private func actionMatching(event: CGEvent) -> ShortcutAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = NSEvent.ModifierFlags(cgEventFlags: event.flags)
        return ShortcutAction.allCases.first { action in
            shortcut(for: action).matches(keyCode: keyCode, flags: flags)
        }
    }

    private func isActionEnabled(_ action: ShortcutAction) -> Bool {
        let snapshot = FrontmostSafariMonitor.shared.snapshot
        guard snapshot.canOverrideSafariShortcuts else { return false }
        switch action {
        case .commandPalette: return snapshot.commandPaletteShortcutEnabled
        case .copyCurrentURL: return snapshot.copyURLShortcutEnabled
        case .toggleSafariSidebar: return snapshot.sidebarShortcutEnabled
        case .profile1, .profile2, .profile3, .profile4, .profile5, .profile6, .profile7, .profile8, .profile9:
            return snapshot.profileShortcutsEnabled
        }
    }

    private func installEventTapIfNeeded() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: shortcutEventTapCallback,
            userInfo: refcon
        ) else {
            isEventTapInstalled = false
            Diagnostics.shared.log("Could not install shortcut event tap. Accessibility permission may be missing.")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        eventTapRunLoopSource = source
        isEventTapInstalled = true
    }

    private func installCarbonEventHandlerIfNeeded() {
        guard carbonEventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(GetApplicationEventTarget(), carbonHotKeyEventHandler, 1, &eventType, refcon, &carbonEventHandler)
        isCarbonHandlerInstalled = status == noErr
    }

    private func reconcileRegisteredHotKeys() {
        guard carbonEventHandler != nil, conflictMessage == nil else {
            unregisterAllHotKeys()
            return
        }
        let desiredActions = Set(ShortcutAction.allCases.filter(isActionEnabled))
        if desiredActions == registeredActions { return }
        unregisterAllHotKeys()
        for action in ShortcutAction.allCases where desiredActions.contains(action) {
            registerHotKey(for: action)
        }
        registeredActions = Set(registeredHotKeys.keys)
    }

    private func registerHotKey(for action: ShortcutAction) {
        let shortcut = shortcut(for: action)
        let hotKeyIDValue = nextHotKeyID
        nextHotKeyID += 1
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: hotKeyIDValue)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifierMask, hotKeyID, GetApplicationEventTarget(), OptionBits(0), &hotKeyRef)
        guard status == noErr, let hotKeyRef else { return }
        registeredHotKeys[action] = hotKeyRef
        actionsByHotKeyID[hotKeyIDValue] = action
    }

    private func unregisterAllHotKeys() {
        for hotKeyRef in registeredHotKeys.values { UnregisterEventHotKey(hotKeyRef) }
        registeredHotKeys.removeAll()
        actionsByHotKeyID.removeAll()
        registeredActions = []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(shortcuts) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private static func loadShortcuts(defaults: UserDefaults, key: String) -> [ShortcutAction: KeyboardShortcut] {
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([ShortcutAction: KeyboardShortcut].self, from: data) {
            var merged = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
            for (action, shortcut) in decoded { merged[action] = shortcut }
            return merged
        }
        return Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    private static func conflictMessage(for shortcuts: [ShortcutAction: KeyboardShortcut]) -> String? {
        let grouped = Dictionary(grouping: shortcuts) { $0.value }
        guard let conflict = grouped.values.first(where: { $0.count > 1 }) else { return nil }
        let actions = conflict.map { $0.key.title }.sorted().joined(separator: ", ")
        return "Shortcut conflict: \(actions) use \(conflict[0].value.displayString)."
    }

    private static let hotKeySignature: OSType = Array("Arkl".utf8).reduce(OSType(0)) { ($0 << 8) + OSType($1) }
}

private let carbonHotKeyEventHandler: EventHandlerUPP = { _, event, refcon in
    guard let event, let refcon else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    let manager = Unmanaged<ShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { manager.handleCarbonHotKey(id: hotKeyID.id) }
}

private let shortcutEventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<ShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { manager.handleEventTap(event: event, type: type) }
}

private extension NSEvent.ModifierFlags {
    init(cgEventFlags: CGEventFlags) {
        var flags: NSEvent.ModifierFlags = []
        if cgEventFlags.contains(.maskCommand) { flags.insert(.command) }
        if cgEventFlags.contains(.maskShift) { flags.insert(.shift) }
        if cgEventFlags.contains(.maskControl) { flags.insert(.control) }
        if cgEventFlags.contains(.maskAlternate) { flags.insert(.option) }
        self = flags
    }
}
