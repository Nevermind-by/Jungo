import AppKit
import Carbon
import Combine

/// Registers a system-wide shortcut without Accessibility permissions or third-party packages.
@MainActor
final class GlobalHotKeyManager: ObservableObject {
    static let shared = GlobalHotKeyManager()

    @Published private(set) var isRegistered = false
    @Published private(set) var registrationError: String?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var openWindowAction: (() -> Void)?
    private var isStarted = false

    private init() {}

    func configure(openWindow: @escaping () -> Void) {
        openWindowAction = openWindow
    }

    func start() {
        guard !isStarted else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            jungoHotKeyHandler,
            1,
            &eventType,
            nil,
            &installedHandler
        )
        guard installStatus == noErr, let installedHandler else {
            registrationError = "Не удалось установить обработчик горячей клавиши (код \(installStatus))."
            NSLog("Jungo: failed to install global hotkey handler (%d)", installStatus)
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4A554E47), id: 1)
        var registeredHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotKey
        )
        guard registerStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            eventHandler = nil
            hotKeyRef = nil
            isStarted = false
            isRegistered = false
            registrationError = "Не удалось зарегистрировать ⌘⌥Space. Возможно, сочетание уже занято другим приложением."
            NSLog("Jungo: failed to register global shortcut ⌘⌥Space (%d)", registerStatus)
            return
        }

        eventHandler = installedHandler
        hotKeyRef = registeredHotKey
        isStarted = true
        isRegistered = true
        registrationError = nil
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKeyRef = nil
        eventHandler = nil
        isStarted = false
        isRegistered = false
    }

    func requestQuickCapture() {
        openQuickCapture()
    }

    fileprivate func handleHotKeyEvent() {
        requestQuickCapture()
    }

    private func openQuickCapture() {
        if let window = NSApp.windows.first(where: { $0.isVisible }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            NotificationCenter.default.post(name: .jungoQuickAddTask, object: nil)
            return
        }

        UserDefaults.standard.set(true, forKey: "jungo.pendingQuickCapture")
        NSApp.activate(ignoringOtherApps: true)
        openWindowAction?()
    }
}

private func jungoHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }

    var pressedHotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &pressedHotKeyID
    )
    guard status == noErr, pressedHotKeyID.signature == OSType(0x4A554E47), pressedHotKeyID.id == 1 else {
        return noErr
    }

    Task { @MainActor in
        GlobalHotKeyManager.shared.handleHotKeyEvent()
    }
    return noErr
}
