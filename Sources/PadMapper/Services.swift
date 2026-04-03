import ApplicationServices
import AppKit
import Foundation
import IOKit.hid

protocol InputDeviceService: AnyObject {
    var events: AsyncStream<InputEvent> { get }
    var devicesStream: AsyncStream<[ManagedInputDevice]> { get }
    func availableDevices() -> [ManagedInputDevice]
    func setActiveDevice(_ deviceID: String?)
    func activeDeviceID() -> String?
    func beginCalibration()
    func endCalibration()
    func simulatePress(physicalKeyID: String)
    func simulateRelease(physicalKeyID: String)
}

final class IOHIDInputDeviceService: NSObject, InputDeviceService {
    let events: AsyncStream<InputEvent>
    let devicesStream: AsyncStream<[ManagedInputDevice]>

    private let eventContinuation: AsyncStream<InputEvent>.Continuation
    private let devicesContinuation: AsyncStream<[ManagedInputDevice]>.Continuation
    private let manager: IOHIDManager

    private var devicesByID: [String: ManagedInputDevice] = [:]
    private var activeDeviceIDValue: String? = ManagedInputDevice.mockPad.id
    private var isCalibrationMode = false

    override init() {
        var eventCont: AsyncStream<InputEvent>.Continuation?
        self.events = AsyncStream { continuation in
            continuation.onTermination = { _ in }
            eventCont = continuation
        }
        self.eventContinuation = eventCont!

        var devicesCont: AsyncStream<[ManagedInputDevice]>.Continuation?
        self.devicesStream = AsyncStream { continuation in
            continuation.onTermination = { _ in }
            devicesCont = continuation
        }
        self.devicesContinuation = devicesCont!

        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        super.init()
        configureManager()
        publishDevices()
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func availableDevices() -> [ManagedInputDevice] {
        [ManagedInputDevice.mockPad] + devicesByID.values.sorted { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    func setActiveDevice(_ deviceID: String?) {
        activeDeviceIDValue = deviceID
    }

    func activeDeviceID() -> String? {
        activeDeviceIDValue
    }

    func beginCalibration() {
        isCalibrationMode = true
    }

    func endCalibration() {
        isCalibrationMode = false
    }

    func simulatePress(physicalKeyID: String) {
        guard activeDeviceIDValue == ManagedInputDevice.mockPad.id else { return }
        eventContinuation.yield(
            InputEvent(
                physicalKeyID: physicalKeyID,
                deviceID: ManagedInputDevice.mockPad.id,
                isPressed: true,
                timestamp: Date(),
                usagePage: nil,
                usage: nil,
                elementCookie: nil
            )
        )
    }

    func simulateRelease(physicalKeyID: String) {
        guard activeDeviceIDValue == ManagedInputDevice.mockPad.id else { return }
        eventContinuation.yield(
            InputEvent(
                physicalKeyID: physicalKeyID,
                deviceID: ManagedInputDevice.mockPad.id,
                isPressed: false,
                timestamp: Date(),
                usagePage: nil,
                usage: nil,
                elementCookie: nil
            )
        )
    }

    private func configureManager() {
        let keyboardMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Keyboard),
        ]
        let keypadMatch: [String: Any] = [
            kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
            kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Keypad),
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, [keyboardMatch, keypadMatch] as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let service = Unmanaged<IOHIDInputDeviceService>.fromOpaque(context).takeUnretainedValue()
            service.handleDeviceConnected(device)
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let service = Unmanaged<IOHIDInputDeviceService>.fromOpaque(context).takeUnretainedValue()
            service.handleDeviceRemoved(device)
        }, context)

        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let service = Unmanaged<IOHIDInputDeviceService>.fromOpaque(context).takeUnretainedValue()
            service.handleInputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        refreshConnectedDevices()
    }

    private func refreshConnectedDevices() {
        guard let set = IOHIDManagerCopyDevices(manager) as NSSet? else {
            publishDevices()
            return
        }

        var newDevices: [String: ManagedInputDevice] = [:]
        for case let device as IOHIDDevice in set {
            if let managedDevice = managedDevice(from: device) {
                newDevices[managedDevice.id] = managedDevice
            }
        }
        devicesByID = newDevices
        publishDevices()
    }

    private func handleDeviceConnected(_ device: IOHIDDevice) {
        guard let managedDevice = managedDevice(from: device) else { return }
        devicesByID[managedDevice.id] = managedDevice
        publishDevices()
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        guard let managedDevice = managedDevice(from: device) else {
            refreshConnectedDevices()
            return
        }

        devicesByID.removeValue(forKey: managedDevice.id)
        if activeDeviceIDValue == managedDevice.id {
            activeDeviceIDValue = nil
        }
        publishDevices()
    }

    private func handleInputValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        guard let managedDevice = managedDevice(from: device) else {
            return
        }
        guard activeDeviceIDValue == managedDevice.id else { return }

        let usagePage = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let cookie = IOHIDElementGetCookie(element)

        guard usagePage == Int(kHIDPage_KeyboardOrKeypad), usage > 0 else {
            return
        }

        let intValue = IOHIDValueGetIntegerValue(value)
        let isPressed = intValue != 0
        let cookieValue = Int(cookie)
        let physicalKeyID = "u\(usagePage)-\(usage)-c\(cookieValue)"

        eventContinuation.yield(
            InputEvent(
                physicalKeyID: physicalKeyID,
                deviceID: managedDevice.id,
                isPressed: isPressed,
                timestamp: Date(),
                usagePage: usagePage,
                usage: usage,
                elementCookie: String(cookieValue)
            )
        )
    }

    private func publishDevices() {
        devicesContinuation.yield(availableDevices())
    }

    private func managedDevice(from device: IOHIDDevice) -> ManagedInputDevice? {
        let vendorId = intProperty(kIOHIDVendorIDKey as CFString, from: device)
        let productId = intProperty(kIOHIDProductIDKey as CFString, from: device)
        let transport = stringProperty(kIOHIDTransportKey as CFString, from: device) ?? "HID"
        let productName = stringProperty(kIOHIDProductKey as CFString, from: device)
        let manufacturer = stringProperty(kIOHIDManufacturerKey as CFString, from: device)
        let serialNumber = stringProperty(kIOHIDSerialNumberKey as CFString, from: device)
        let locationId = stringProperty(kIOHIDLocationIDKey as CFString, from: device) ?? intProperty(kIOHIDLocationIDKey as CFString, from: device).map(String.init)

        let deviceID = Self.deviceID(
            vendorId: vendorId,
            productId: productId,
            transport: transport,
            locationId: locationId,
            serialNumber: serialNumber
        )

        let name = [manufacturer, productName]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .nilIfEmpty ?? productName ?? "HID Keyboard"

        let statusText = "\(transport) · 监听模式"

        return ManagedInputDevice(
            id: deviceID,
            name: name,
            transport: transport,
            statusText: statusText,
            vendorId: vendorId,
            productId: productId,
            locationId: locationId,
            serialNumber: serialNumber,
            isConnected: true,
            isMock: false
        )
    }

    private func intProperty(_ key: CFString, from device: IOHIDDevice) -> Int? {
        if let number = IOHIDDeviceGetProperty(device, key) as? NSNumber {
            return number.intValue
        }
        return nil
    }

    private func stringProperty(_ key: CFString, from device: IOHIDDevice) -> String? {
        if let string = IOHIDDeviceGetProperty(device, key) as? String {
            return string
        }
        if let number = IOHIDDeviceGetProperty(device, key) as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func deviceID(
        vendorId: Int?,
        productId: Int?,
        transport: String,
        locationId: String?,
        serialNumber: String?
    ) -> String {
        let vendor = vendorId.map(String.init) ?? "unknown"
        let product = productId.map(String.init) ?? "unknown"
        let stableSuffix = locationId?.nilIfEmpty ?? serialNumber?.nilIfEmpty ?? "noloc"
        return "hid:\(transport.lowercased()):\(vendor):\(product):\(stableSuffix)"
    }
}

protocol ProfileStore {
    var storageURL: URL { get }
    func loadProfile() throws -> DeviceProfile?
    func saveProfile(_ profile: DeviceProfile) throws
}

struct JSONProfileStore: ProfileStore {
    let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PadMapper", isDirectory: true)
        self.storageURL = baseURL.appendingPathComponent("profile.json")
    }

    func loadProfile() throws -> DeviceProfile? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: storageURL)
        return try decoder.decode(DeviceProfile.self, from: data)
    }

    func saveProfile(_ profile: DeviceProfile) throws {
        let directoryURL = storageURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: storageURL, options: .atomic)
    }
}

protocol AccessibilityPermissionChecking {
    func isTrusted() -> Bool
    func prompt()
}

struct SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func prompt() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}

protocol ShortcutActionPerforming {
    func perform(_ shortcut: ShortcutSpec) throws
}

protocol MediaKeyActionPerforming {
    func perform(_ mediaKey: MediaKeyType) throws
}

enum ShortcutExecutionError: LocalizedError {
    case unsupportedKey(String)
    case missingEventSource
    case missingShortcut

    var errorDescription: String? {
        switch self {
        case .unsupportedKey(let key): "不支持的快捷键按键：\(key)"
        case .missingEventSource: "无法创建系统事件源"
        case .missingShortcut: "功能单元未配置快捷键"
        }
    }
}

enum MediaKeyExecutionError: LocalizedError {
    case unsupportedMediaKey

    var errorDescription: String? {
        switch self {
        case .unsupportedMediaKey: "不支持的多媒体键类型"
        }
    }
}

struct LiveShortcutExecutor: ShortcutActionPerforming {
    func perform(_ shortcut: ShortcutSpec) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw ShortcutExecutionError.missingEventSource
        }

        let keyCode = try KeyCodeMapper.keyCode(for: shortcut.key)
        let modifierKeyCodes = shortcut.modifiers.compactMap(KeyCodeMapper.modifierKeyCode(for:))
        let flags = KeyCodeMapper.flags(for: shortcut.modifiers)

        for modifierKeyCode in modifierKeyCodes {
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifierKeyCode, keyDown: true)
            event?.post(tap: .cghidEventTap)
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)

        for modifierKeyCode in modifierKeyCodes.reversed() {
            let event = CGEvent(keyboardEventSource: source, virtualKey: modifierKeyCode, keyDown: false)
            event?.post(tap: .cghidEventTap)
        }
    }
}

struct LiveMediaKeyExecutor: MediaKeyActionPerforming {
    func perform(_ mediaKey: MediaKeyType) throws {
        guard let keyType = mediaKey.systemKeyType else {
            throw MediaKeyExecutionError.unsupportedMediaKey
        }
        postMediaKey(keyType: keyType, keyDown: true)
        postMediaKey(keyType: keyType, keyDown: false)
    }

    private func postMediaKey(keyType: Int32, keyDown: Bool) {
        let keyState = keyDown ? 0xA : 0xB
        let data1 = Int((UInt32(bitPattern: keyType) << 16) | UInt32(keyState << 8))
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }
}

struct LoggingActionExecutor {
    func execute(_ functionUnit: FunctionUnit, reason: String) -> ActionExecutionResult {
        ActionExecutionResult(usedLiveExecution: false, message: "[日志回退] \(functionUnit.name): \(reason)")
    }
}

protocol ActionExecutor: AnyObject {
    var permissionState: AccessibilityPermissionState { get }
    func refreshPermissionState()
    func requestAccessibilityPermission()
    func execute(functionUnit: FunctionUnit) -> ActionExecutionResult
}

final class CompositeActionExecutor: ActionExecutor {
    private let permissionChecker: AccessibilityPermissionChecking
    private let liveShortcutExecutor: ShortcutActionPerforming
    private let liveMediaKeyExecutor: MediaKeyActionPerforming
    private let loggingExecutor: LoggingActionExecutor

    private(set) var permissionState: AccessibilityPermissionState

    init(
        permissionChecker: AccessibilityPermissionChecking = SystemAccessibilityPermissionChecker(),
        liveExecutor: ShortcutActionPerforming = LiveShortcutExecutor(),
        liveMediaKeyExecutor: MediaKeyActionPerforming = LiveMediaKeyExecutor(),
        loggingExecutor: LoggingActionExecutor = LoggingActionExecutor()
    ) {
        self.permissionChecker = permissionChecker
        self.liveShortcutExecutor = liveExecutor
        self.liveMediaKeyExecutor = liveMediaKeyExecutor
        self.loggingExecutor = loggingExecutor
        self.permissionState = permissionChecker.isTrusted() ? .authorized : .needsPermission
    }

    func refreshPermissionState() {
        permissionState = permissionChecker.isTrusted() ? .authorized : .needsPermission
    }

    func requestAccessibilityPermission() {
        permissionChecker.prompt()
        refreshPermissionState()
    }

    func execute(functionUnit: FunctionUnit) -> ActionExecutionResult {
        guard let action = functionUnit.actions.first else {
            return loggingExecutor.execute(functionUnit, reason: ShortcutExecutionError.missingShortcut.localizedDescription)
        }

        guard permissionState == .authorized else {
            return loggingExecutor.execute(functionUnit, reason: "缺少辅助功能权限，已改为记录日志")
        }

        switch action.type {
        case .shortcut:
            guard let shortcut = action.shortcut else {
                return loggingExecutor.execute(functionUnit, reason: ShortcutExecutionError.missingShortcut.localizedDescription)
            }
            do {
                try liveShortcutExecutor.perform(shortcut)
                let renderedShortcut = KeyCodeMapper.render(shortcut: shortcut)
                return ActionExecutionResult(usedLiveExecution: true, message: "已触发 \(functionUnit.name) -> \(renderedShortcut)")
            } catch {
                return loggingExecutor.execute(functionUnit, reason: error.localizedDescription)
            }
        case .mediaKey:
            guard let mediaKey = action.mediaKey else {
                return loggingExecutor.execute(functionUnit, reason: "功能单元未配置多媒体键")
            }
            do {
                try liveMediaKeyExecutor.perform(mediaKey)
                return ActionExecutionResult(usedLiveExecution: true, message: "已触发 \(functionUnit.name) -> \(mediaKey.title)")
            } catch {
                return loggingExecutor.execute(functionUnit, reason: error.localizedDescription)
            }
        }
    }
}

private extension MediaKeyType {
    var systemKeyType: Int32? {
        switch self {
        case .playPause:
            return 16
        case .nextTrack:
            return 17
        case .previousTrack:
            return 18
        case .volumeUp:
            return 0
        case .volumeDown:
            return 1
        case .mute:
            return 7
        }
    }
}

enum KeyCodeMapper {
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
        "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
        "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
        "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "tab": 0x30, "space": 0x31,
        "`": 0x32, "delete": 0x33, "escape": 0x35, "command": 0x37, "shift": 0x38, "capslock": 0x39,
        "option": 0x3A, "control": 0x3B, "rightshift": 0x3C, "rightoption": 0x3D, "rightcontrol": 0x3E,
        "fn": 0x3F, "f17": 0x40, "volumeup": 0x48, "volumedown": 0x49, "mute": 0x4A, "f18": 0x4F,
        "f19": 0x50, "f20": 0x5A, "f5": 0x60, "f6": 0x61, "f7": 0x62, "f3": 0x63, "f8": 0x64,
        "f9": 0x65, "f11": 0x67, "f13": 0x69, "f16": 0x6A, "f14": 0x6B, "f10": 0x6D, "f12": 0x6F,
        "f15": 0x71, "help": 0x72, "home": 0x73, "pageup": 0x74, "forwarddelete": 0x75, "f4": 0x76,
        "end": 0x77, "f2": 0x78, "pagedown": 0x79, "f1": 0x7A, "left": 0x7B, "right": 0x7C,
        "down": 0x7D, "up": 0x7E, "return": 0x24
    ]

    static func keyCode(for key: String) throws -> CGKeyCode {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let code = keyCodes[normalized] else {
            throw ShortcutExecutionError.unsupportedKey(key)
        }
        return code
    }

    static func modifierKeyCode(for modifier: ShortcutModifier) -> CGKeyCode? {
        switch modifier {
        case .command: keyCodes["command"]
        case .shift: keyCodes["shift"]
        case .option: keyCodes["option"]
        case .control: keyCodes["control"]
        case .function: keyCodes["fn"]
        }
    }

    static func flags(for modifiers: [ShortcutModifier]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .shift: flags.insert(.maskShift)
            case .option: flags.insert(.maskAlternate)
            case .control: flags.insert(.maskControl)
            case .function: flags.insert(.maskSecondaryFn)
            }
        }
    }

    static func render(shortcut: ShortcutSpec) -> String {
        let modifierText = shortcut.modifiers.map(\.title).joined(separator: "+")
        let keyText = shortcut.key.uppercased()
        if modifierText.isEmpty {
            return keyText
        }
        return "\(modifierText)+\(keyText)"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
