import AppKit
import Carbon
import SwiftUI

/// Minimal global hotkey support using Carbon RegisterEventHotKey.
/// Zero external dependencies; works with Command Line Tools only.
@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public struct Shortcut: Codable, Equatable, Sendable {
        public var keyCode: UInt32
        public var modifiers: UInt32 // Carbon modifier flags

        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// Default: ⌃⌥⌘G
        public static let defaultPicker = Shortcut(
            keyCode: UInt32(kVK_ANSI_G),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        )

        public var displayString: String {
            var s = ""
            if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
            s += KeyCodeNames.name(for: keyCode)
            return s
        }
    }

    private var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var current: Shortcut?

    private init() {
        installHandlerIfNeeded()
    }

    public var currentShortcut: Shortcut {
        if let current { return current }
        if let saved = Self.loadSaved() { return saved }
        return .defaultPicker
    }

    public func register(shortcut: Shortcut, handler: @escaping () -> Void) {
        unregister()
        self.handler = handler
        self.current = shortcut

        var hotKeyRef: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x41505442), id: 1) // 'APTB'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if status == noErr {
            self.hotKeyRef = hotKeyRef
            Self.save(shortcut)
        } else {
            NSLog("AppTabs: RegisterEventHotKey failed: \(status)")
        }
    }

    public func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Carbon event plumbing

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, context -> OSStatus in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in center.handler?() }
            return noErr
        }, 1, &spec, context, &eventHandlerRef)
    }

    // MARK: - Persistence

    private static let defaultsKey = "pickerShortcut"

    private static func loadSaved() -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Shortcut.self, from: data)
    }

    private static func save(_ shortcut: Shortcut) {
        if let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}

/// Key code → display name.
enum KeyCodeNames {
    static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"; case kVK_ANSI_B: return "B"; case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"; case kVK_ANSI_E: return "E"; case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"; case kVK_ANSI_H: return "H"; case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"; case kVK_ANSI_K: return "K"; case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"; case kVK_ANSI_N: return "N"; case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"; case kVK_ANSI_Q: return "Q"; case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"; case kVK_ANSI_T: return "T"; case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"; case kVK_ANSI_W: return "W"; case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"; case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"; case kVK_ANSI_1: return "1"; case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"; case kVK_ANSI_4: return "4"; case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"; case kVK_ANSI_7: return "7"; case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Space"; case kVK_Return: return "↩"; case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"; case kVK_F1: return "F1"; case kVK_F2: return "F2"
        case kVK_F3: return "F3"; case kVK_F4: return "F4"; case kVK_F5: return "F5"
        case kVK_F6: return "F6"; case kVK_F7: return "F7"; case kVK_F8: return "F8"
        case kVK_F9: return "F9"; case kVK_F10: return "F10"; case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_LeftArrow: return "←"; case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"; case kVK_DownArrow: return "↓"
        default: return "?"
        }
    }
}

/// SwiftUI recorder field: click, press a key combo, it's captured.
public struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var shortcut: HotKeyCenter.Shortcut
    var onChange: (HotKeyCenter.Shortcut) -> Void

    public init(shortcut: Binding<HotKeyCenter.Shortcut>, onChange: @escaping (HotKeyCenter.Shortcut) -> Void) {
        self._shortcut = shortcut
        self.onChange = onChange
    }

    public func makeNSView(context: Context) -> ShortcutRecorderField {
        let field = ShortcutRecorderField()
        field.onCapture = { new in
            shortcut = new
            onChange(new)
        }
        return field
    }

    public func updateNSView(_ nsView: ShortcutRecorderField, context: Context) {
        nsView.shortcut = shortcut
    }
}

public final class ShortcutRecorderField: NSTextField {
    var shortcut: HotKeyCenter.Shortcut = .defaultPicker {
        didSet { stringValue = shortcut.displayString }
    }
    var onCapture: ((HotKeyCenter.Shortcut) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEditable = false
        isBezeled = true
        alignment = .center
        stringValue = shortcut.displayString
    }

    public required init?(coder: NSCoder) { fatalError() }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func keyDown(with event: NSEvent) {
        var mods: UInt32 = 0
        if event.modifierFlags.contains(.control) { mods |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { mods |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { mods |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods != 0 else { return } // require at least one modifier
        let new = HotKeyCenter.Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods)
        shortcut = new
        onCapture?(new)
        window?.makeFirstResponder(nil)
    }
}
