import AppKit
import Carbon.HIToolbox
import Foundation

struct KeyboardShortcut: Codable, Equatable, Hashable, Identifiable {
    var id: String { "\(keyCode)-\(modifierMask)" }

    let keyCode: UInt16
    let modifierMask: UInt

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierMask = KeyboardShortcut.normalized(modifiers).rawValue
    }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierMask)
    }

    var displayString: String {
        var parts: [String] = []
        let normalized = KeyboardShortcut.normalized(modifiers)
        if normalized.contains(.control) { parts.append("⌃") }
        if normalized.contains(.option) { parts.append("⌥") }
        if normalized.contains(.shift) { parts.append("⇧") }
        if normalized.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyDisplayName(for: keyCode))
        return parts.joined()
    }

    var carbonModifierMask: UInt32 {
        var carbon: UInt32 = 0
        let normalized = KeyboardShortcut.normalized(modifiers)
        if normalized.contains(.command) { carbon |= UInt32(cmdKey) }
        if normalized.contains(.shift) { carbon |= UInt32(shiftKey) }
        if normalized.contains(.option) { carbon |= UInt32(optionKey) }
        if normalized.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    func matches(keyCode candidateKeyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == candidateKeyCode && modifiers == Self.normalized(flags)
    }

    static func normalized(_ modifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifiers.intersection([.command, .shift, .control, .option])
    }

    static func from(event: NSEvent) -> KeyboardShortcut? {
        guard event.type == .keyDown else { return nil }
        let modifiers = normalized(event.modifierFlags)
        guard !modifiers.isEmpty else { return nil }
        return KeyboardShortcut(keyCode: UInt16(event.keyCode), modifiers: modifiers)
    }

    static func keyDisplayName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: "A"
        case kVK_ANSI_B: "B"
        case kVK_ANSI_C: "C"
        case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"
        case kVK_ANSI_F: "F"
        case kVK_ANSI_G: "G"
        case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"
        case kVK_ANSI_J: "J"
        case kVK_ANSI_K: "K"
        case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"
        case kVK_ANSI_N: "N"
        case kVK_ANSI_O: "O"
        case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"
        case kVK_ANSI_R: "R"
        case kVK_ANSI_S: "S"
        case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"
        case kVK_ANSI_V: "V"
        case kVK_ANSI_W: "W"
        case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"
        case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"
        case kVK_ANSI_1: "1"
        case kVK_ANSI_2: "2"
        case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"
        case kVK_ANSI_5: "5"
        case kVK_ANSI_6: "6"
        case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"
        case kVK_ANSI_9: "9"
        case kVK_Space: "Space"
        case kVK_Return: "Return"
        case kVK_Escape: "Esc"
        default: "Key \(keyCode)"
        }
    }
}

enum ShortcutAction: String, CaseIterable, Codable, Identifiable {
    case commandPalette
    case copyCurrentURL
    case toggleSafariSidebar
    case profile1
    case profile2
    case profile3
    case profile4
    case profile5
    case profile6
    case profile7
    case profile8
    case profile9

    var id: String { rawValue }

    var title: String {
        switch self {
        case .commandPalette: "Open Command Palette"
        case .copyCurrentURL: "Copy Current URL"
        case .toggleSafariSidebar: "Toggle Safari Sidebar"
        case .profile1: "Switch to Profile 1"
        case .profile2: "Switch to Profile 2"
        case .profile3: "Switch to Profile 3"
        case .profile4: "Switch to Profile 4"
        case .profile5: "Switch to Profile 5"
        case .profile6: "Switch to Profile 6"
        case .profile7: "Switch to Profile 7"
        case .profile8: "Switch to Profile 8"
        case .profile9: "Switch to Profile 9"
        }
    }

    var profileNumber: Int? {
        switch self {
        case .profile1: 1
        case .profile2: 2
        case .profile3: 3
        case .profile4: 4
        case .profile5: 5
        case .profile6: 6
        case .profile7: 7
        case .profile8: 8
        case .profile9: 9
        default: nil
        }
    }

    var defaultShortcut: KeyboardShortcut {
        switch self {
        case .commandPalette:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_T), modifiers: .command)
        case .copyCurrentURL:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command, .shift])
        case .toggleSafariSidebar:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: .command)
        case .profile1:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_1), modifiers: .control)
        case .profile2:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_2), modifiers: .control)
        case .profile3:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_3), modifiers: .control)
        case .profile4:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_4), modifiers: .control)
        case .profile5:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_5), modifiers: .control)
        case .profile6:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_6), modifiers: .control)
        case .profile7:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_7), modifiers: .control)
        case .profile8:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_8), modifiers: .control)
        case .profile9:
            KeyboardShortcut(keyCode: UInt16(kVK_ANSI_9), modifiers: .control)
        }
    }
}
