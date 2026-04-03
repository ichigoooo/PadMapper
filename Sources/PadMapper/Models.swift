import Foundation
import SwiftUI

enum KeyShapeType: String, Codable, CaseIterable, Identifiable, Sendable {
    case rect
    case wide
    case lshape

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rect: "矩形"
        case .wide: "宽键"
        case .lshape: "L 形"
        }
    }
}

enum PadColorToken: String, Codable, CaseIterable, Identifiable, Sendable {
    case slate
    case teal
    case amber
    case coral
    case indigo
    case olive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slate: "灰蓝"
        case .teal: "青绿"
        case .amber: "琥珀"
        case .coral: "珊瑚"
        case .indigo: "靛蓝"
        case .olive: "橄榄"
        }
    }

    var color: Color {
        switch self {
        case .slate: Color(red: 0.41, green: 0.49, blue: 0.62)
        case .teal: Color(red: 0.12, green: 0.62, blue: 0.60)
        case .amber: Color(red: 0.90, green: 0.66, blue: 0.16)
        case .coral: Color(red: 0.89, green: 0.42, blue: 0.39)
        case .indigo: Color(red: 0.37, green: 0.44, blue: 0.82)
        case .olive: Color(red: 0.49, green: 0.60, blue: 0.24)
        }
    }
}

struct PhysicalInputRef: Codable, Hashable, Identifiable, Sendable {
    let deviceId: String
    let physicalKeyID: String
    var usagePage: Int?
    var usage: Int?
    var elementCookie: String?

    var id: String { "\(deviceId):\(physicalKeyID)" }
}

struct LayoutKey: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var row: Int
    var col: Int
    var width: Int
    var height: Int
    var shapeType: KeyShapeType
    var label: String
    var colorToken: PadColorToken
    var calibrateBinding: PhysicalInputRef?

    var defaultPhysicalKeyID: String {
        "P\(String(format: "%02d", row * 6 + col))"
    }
}

enum ShortcutModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case command
    case shift
    case option
    case control
    case function

    var id: String { rawValue }

    var title: String {
        switch self {
        case .command: "Cmd"
        case .shift: "Shift"
        case .option: "Opt"
        case .control: "Ctrl"
        case .function: "Fn"
        }
    }
}

struct ShortcutSpec: Codable, Hashable, Sendable {
    var modifiers: [ShortcutModifier]
    var key: String
}

enum MediaKeyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case playPause
    case nextTrack
    case previousTrack
    case volumeUp
    case volumeDown
    case mute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .playPause: "播放/暂停"
        case .nextTrack: "下一曲"
        case .previousTrack: "上一曲"
        case .volumeUp: "音量+"
        case .volumeDown: "音量-"
        case .mute: "静音"
        }
    }
}

enum OutputActionType: String, Codable, Sendable {
    case shortcut
    case mediaKey
}

struct OutputAction: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var type: OutputActionType
    var shortcut: ShortcutSpec?
    var mediaKey: MediaKeyType?

    static func shortcut(id: String = UUID().uuidString, modifiers: [ShortcutModifier], key: String) -> OutputAction {
        OutputAction(id: id, type: .shortcut, shortcut: ShortcutSpec(modifiers: modifiers, key: key), mediaKey: nil)
    }

    static func mediaKey(id: String = UUID().uuidString, key: MediaKeyType) -> OutputAction {
        OutputAction(id: id, type: .mediaKey, shortcut: nil, mediaKey: key)
    }
}

struct FunctionUnit: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var description: String?
    var actions: [OutputAction]
    var enabled: Bool
}

enum TriggerType: String, Codable, CaseIterable, Identifiable, Sendable {
    case single
    case combo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: "单键"
        case .combo: "组合"
        }
    }
}

enum TriggerInputMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case logical
    case physical

    var id: String { rawValue }

    var title: String {
        switch self {
        case .logical: "逻辑键"
        case .physical: "物理键码"
        }
    }
}

struct BindingRule: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var triggerKeys: [String]
    var triggerType: TriggerType
    var triggerInputMode: TriggerInputMode = .logical
    var triggerWindowMs: Int
    var suppressIndividualKeys: Bool
    var functionUnitId: String
    var enabled: Bool
    var priority: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case triggerKeys
        case triggerType
        case triggerInputMode
        case triggerWindowMs
        case suppressIndividualKeys
        case functionUnitId
        case enabled
        case priority
    }

    init(
        id: String,
        triggerKeys: [String],
        triggerType: TriggerType,
        triggerInputMode: TriggerInputMode = .logical,
        triggerWindowMs: Int,
        suppressIndividualKeys: Bool,
        functionUnitId: String,
        enabled: Bool,
        priority: Int
    ) {
        self.id = id
        self.triggerKeys = triggerKeys
        self.triggerType = triggerType
        self.triggerInputMode = triggerInputMode
        self.triggerWindowMs = triggerWindowMs
        self.suppressIndividualKeys = suppressIndividualKeys
        self.functionUnitId = functionUnitId
        self.enabled = enabled
        self.priority = priority
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        triggerKeys = try container.decode([String].self, forKey: .triggerKeys)
        triggerType = try container.decode(TriggerType.self, forKey: .triggerType)
        triggerInputMode = try container.decodeIfPresent(TriggerInputMode.self, forKey: .triggerInputMode) ?? .logical
        triggerWindowMs = try container.decode(Int.self, forKey: .triggerWindowMs)
        suppressIndividualKeys = try container.decode(Bool.self, forKey: .suppressIndividualKeys)
        functionUnitId = try container.decode(String.self, forKey: .functionUnitId)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        priority = try container.decode(Int.self, forKey: .priority)
    }
}

struct DeviceMatch: Codable, Hashable, Sendable {
    var vendorId: Int?
    var productId: Int?
    var transport: String?
    var serialNumber: String?
    var locationId: String?
}

struct DeviceProfile: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var name: String
    var deviceMatch: DeviceMatch
    var layout: [LayoutKey]
    var functionUnits: [FunctionUnit]
    var rules: [BindingRule]
    var isEnabled: Bool

    static func defaultProfile() -> DeviceProfile {
        let layout = (0..<3).flatMap { row in
            (0..<6).map { col in
                let index = row * 6 + col
                return LayoutKey(
                    id: "K\(String(format: "%02d", index))",
                    row: row,
                    col: col,
                    width: 1,
                    height: 1,
                    shapeType: .rect,
                    label: "K\(index + 1)",
                    colorToken: [.slate, .teal, .amber, .coral, .indigo, .olive][index % 6],
                    calibrateBinding: PhysicalInputRef(
                        deviceId: "mock-pad",
                        physicalKeyID: "P\(String(format: "%02d", index))",
                        usagePage: nil,
                        usage: nil,
                        elementCookie: nil
                    )
                )
            }
        }

        let redoUnit = FunctionUnit(
            id: UUID().uuidString,
            name: "Redo",
            description: "示例功能单元",
            actions: [.shortcut(modifiers: [.command], key: "y")],
            enabled: true
        )

        return DeviceProfile(
            id: UUID().uuidString,
            name: "Mock Pad 配置",
            deviceMatch: DeviceMatch(vendorId: nil, productId: nil, transport: "mock", serialNumber: nil, locationId: nil),
            layout: layout,
            functionUnits: [redoUnit],
            rules: [],
            isEnabled: true
        )
    }
}

struct ManagedInputDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let transport: String
    let statusText: String
    let vendorId: Int?
    let productId: Int?
    let locationId: String?
    let serialNumber: String?
    let isConnected: Bool
    let isMock: Bool

    var deviceMatch: DeviceMatch {
        DeviceMatch(
            vendorId: vendorId,
            productId: productId,
            transport: transport,
            serialNumber: serialNumber,
            locationId: locationId
        )
    }

    static let mockPad = ManagedInputDevice(
        id: "mock-pad",
        name: "Mock Pad",
        transport: "模拟设备",
        statusText: "测试模式，可随时回退",
        vendorId: nil,
        productId: nil,
        locationId: nil,
        serialNumber: nil,
        isConnected: true,
        isMock: true
    )
}

enum InputSourceMode: String, Sendable {
    case mock
    case hid
    case none

    var title: String {
        switch self {
        case .mock: "测试模式"
        case .hid: "真实设备"
        case .none: "未选择输入源"
        }
    }
}

struct InputEvent: Hashable, Sendable {
    let physicalKeyID: String
    let deviceID: String
    let isPressed: Bool
    let timestamp: Date
    let usagePage: Int?
    let usage: Int?
    let elementCookie: String?
}

struct PressedKeyState: Hashable, Sendable {
    let logicalKeyID: String
    let pressedAt: Date
}

struct TriggerMatch: Identifiable, Hashable, Sendable {
    let id: String
    let ruleID: String
    let functionUnitID: String
    let triggerKeys: [String]
}

struct DebugSnapshot: Hashable, Sendable {
    var activePhysicalKeys: [String]
    var activeLogicalKeys: [String]
    var candidateRuleIDs: [String]
    var winningRuleID: String?
    var firedRuleIDs: [String]
    var pendingSingleRuleIDs: [String]
    var outputLog: [String]

    static let empty = DebugSnapshot(
        activePhysicalKeys: [],
        activeLogicalKeys: [],
        candidateRuleIDs: [],
        winningRuleID: nil,
        firedRuleIDs: [],
        pendingSingleRuleIDs: [],
        outputLog: []
    )
}

enum AccessibilityPermissionState: String, Sendable {
    case authorized
    case needsPermission

    var title: String {
        switch self {
        case .authorized: "已授权"
        case .needsPermission: "需要辅助功能权限"
        }
    }
}

struct ActionExecutionResult: Sendable {
    let usedLiveExecution: Bool
    let message: String
}

struct RuntimeFeedbackEntry: Identifiable, Hashable, Sendable {
    let id: String
    let timestamp: Date
    let message: String
}

enum NoticeLevel: String, Hashable, Sendable {
    case info
    case success
    case warning
    case error
}

struct PrimaryNotice: Hashable, Sendable {
    var level: NoticeLevel
    var title: String
    var message: String
    var details: String?

    var fullText: String {
        [message, details].compactMap { $0?.nilIfEmpty }.joined(separator: " ")
    }
}

enum WorkflowStep: String, Hashable, Sendable {
    case waitingForKeys
    case readyToPin
    case configureGroup

    var title: String {
        switch self {
        case .waitingForKeys:
            return "等待按键"
        case .readyToPin:
            return "可以固定"
        case .configureGroup:
            return "配置动作"
        }
    }

    var summary: String {
        switch self {
        case .waitingForKeys:
            return "先在目标小键盘上按下想归为一组的键。"
        case .readyToPin:
            return "当前已经识别到按键，可以直接固定成按键组。"
        case .configureGroup:
            return "按键组已经就绪，下一步在右侧配置动作并确认。"
        }
    }
}

extension DeviceMatch {
    func matches(device: ManagedInputDevice) -> Bool {
        if transport == "mock" || device.isMock {
            return transport == device.transport || device.id == ManagedInputDevice.mockPad.id
        }

        guard vendorId == device.vendorId, productId == device.productId, transport == device.transport else {
            return false
        }

        if let locationId, !locationId.isEmpty, let deviceLocationId = device.locationId, !deviceLocationId.isEmpty {
            return locationId == deviceLocationId
        }

        return true
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
