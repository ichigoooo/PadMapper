import Foundation
import Testing
@testable import PadMapper

@Test func profileRoundTripPersists() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    var profile = DeviceProfile.defaultProfile()
    profile.rules = [
        BindingRule(
            id: "rule",
            triggerKeys: ["u7-4-c10", "u7-5-c11", "u7-6-c12"],
            triggerType: .combo,
            triggerInputMode: .physical,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: profile.functionUnits[0].id,
            enabled: true,
            priority: 100
        )
    ]

    try store.saveProfile(profile)
    let loaded = try store.loadProfile()

    #expect(loaded == profile)
}

@Test func actionExecutorFallsBackWithoutPermission() async throws {
    let checker = FakePermissionChecker(isTrustedValue: false)
    let performer = FakeShortcutPerformer()
    let executor = CompositeActionExecutor(permissionChecker: checker, liveExecutor: performer)
    let functionUnit = FunctionUnit(id: "unit", name: "Redo", description: nil, actions: [.shortcut(modifiers: [.command], key: "y")], enabled: true)

    let result = executor.execute(functionUnit: functionUnit)

    #expect(result.usedLiveExecution == false)
    #expect(result.message.contains("日志回退"))
    #expect(performer.performCount == 0)
}

@Test func actionExecutorUsesLiveWhenAuthorized() async throws {
    let checker = FakePermissionChecker(isTrustedValue: true)
    let performer = FakeShortcutPerformer()
    let executor = CompositeActionExecutor(permissionChecker: checker, liveExecutor: performer)
    let functionUnit = FunctionUnit(id: "unit", name: "Redo", description: nil, actions: [.shortcut(modifiers: [.command], key: "y")], enabled: true)

    let result = executor.execute(functionUnit: functionUnit)

    #expect(result.usedLiveExecution == true)
    #expect(performer.performCount == 1)
    #expect(result.message.contains("Redo"))
}

@Test func actionExecutorUsesLiveMediaKeyWhenAuthorized() async throws {
    let checker = FakePermissionChecker(isTrustedValue: true)
    let shortcutPerformer = FakeShortcutPerformer()
    let mediaPerformer = FakeMediaKeyPerformer()
    let executor = CompositeActionExecutor(
        permissionChecker: checker,
        liveExecutor: shortcutPerformer,
        liveMediaKeyExecutor: mediaPerformer
    )
    let functionUnit = FunctionUnit(
        id: "unit",
        name: "Play",
        description: nil,
        actions: [.mediaKey(key: .playPause)],
        enabled: true
    )

    let result = executor.execute(functionUnit: functionUnit)

    #expect(result.usedLiveExecution == true)
    #expect(mediaPerformer.performCount == 1)
    #expect(shortcutPerformer.performCount == 0)
}

@Test func deviceMatchFallsBackWithoutLocation() async throws {
    let match = DeviceMatch(vendorId: 1000, productId: 2000, transport: "USB", serialNumber: nil, locationId: "123")
    let device = ManagedInputDevice(
        id: "hid:usb:1000:2000:999",
        name: "Test Pad",
        transport: "USB",
        statusText: "USB · 监听模式",
        vendorId: 1000,
        productId: 2000,
        locationId: "999",
        serialNumber: nil,
        isConnected: true,
        isMock: false
    )

    #expect(match.matches(device: device) == false)

    let fallbackMatch = DeviceMatch(vendorId: 1000, productId: 2000, transport: "USB", serialNumber: nil, locationId: nil)
    #expect(fallbackMatch.matches(device: device) == true)
}

@MainActor
@Test func pinCurrentPressedComboRejectsOccupiedKeys() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    let functionUnit = FunctionUnit(
        id: "occupied-unit",
        name: "撤销组",
        description: nil,
        actions: [.shortcut(modifiers: [.command], key: "z")],
        enabled: true
    )
    var profile = DeviceProfile.defaultProfile()
    profile.functionUnits = [functionUnit]
    profile.rules = [
        BindingRule(
            id: "occupied-rule",
            triggerKeys: ["u7-89-c978", "u7-90-c979"],
            triggerType: .combo,
            triggerInputMode: .physical,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: functionUnit.id,
            enabled: true,
            priority: 100
        )
    ]
    try store.saveProfile(profile)

    let model = AppModel(
        inputService: FakeInputDeviceService(),
        profileStore: store,
        actionExecutor: FakeActionExecutor()
    )
    model.debugSnapshot = DebugSnapshot(
        activePhysicalKeys: ["u7-90-c979", "u7-91-c980"],
        activeLogicalKeys: [],
        candidateRuleIDs: [],
        winningRuleID: nil,
        firedRuleIDs: [],
        pendingSingleRuleIDs: [],
        outputLog: []
    )

    model.pinCurrentPressedCombo()

    #expect(model.profile.rules.count == 1)
    #expect(model.selectedRuleID == "occupied-rule")
    #expect(model.statusMessage.contains("有按键和已有组合冲突"))
    #expect(model.statusMessage.contains("u7-90-c979"))
    #expect(model.statusMessage.contains("撤销组"))
    #expect(model.feedbackEntries.last?.message.contains("有按键和已有组合冲突") == true)
}

@MainActor
@Test func workflowStepTracksPressedKeysAndSavedGroups() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    let model = AppModel(
        inputService: FakeInputDeviceService(),
        profileStore: store,
        actionExecutor: FakeActionExecutor()
    )

    #expect(model.workflowStep == .waitingForKeys)

    model.debugSnapshot = DebugSnapshot(
        activePhysicalKeys: ["u7-89-c978"],
        activeLogicalKeys: [],
        candidateRuleIDs: [],
        winningRuleID: nil,
        firedRuleIDs: [],
        pendingSingleRuleIDs: [],
        outputLog: []
    )
    #expect(model.workflowStep == .readyToPin)

    model.pinCurrentPressedCombo()
    model.debugSnapshot = .empty
    #expect(model.workflowStep == .configureGroup)
    #expect(model.primaryNotice.title == "已固定按键组")
}

@MainActor
@Test func confirmSelectedGroupConfigurationUpdatesNameAndNotice() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    let model = AppModel(
        inputService: FakeInputDeviceService(),
        profileStore: store,
        actionExecutor: FakeActionExecutor()
    )
    model.debugSnapshot = DebugSnapshot(
        activePhysicalKeys: ["u7-89-c978"],
        activeLogicalKeys: [],
        candidateRuleIDs: [],
        winningRuleID: nil,
        firedRuleIDs: [],
        pendingSingleRuleIDs: [],
        outputLog: []
    )
    model.pinCurrentPressedCombo()

    model.confirmSelectedGroupConfiguration(
        name: "复制组",
        actionType: .shortcut,
        shortcutKey: "c",
        modifiers: [.command],
        mediaKey: .playPause
    )

    #expect(model.selectedRuleDisplayName == "复制组")
    #expect(model.currentActionSummaryText == "Cmd+C")
    #expect(model.primaryNotice.title == "已保存按键组配置")
    #expect(model.feedbackEntries.last?.message.contains("已保存按键组配置") == true)
    #expect(model.lastConfigSavedAt != nil)
}

@MainActor
@Test func clearWorkflowStateResetsProgressWithoutDeletingRules() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    let model = AppModel(
        inputService: FakeInputDeviceService(),
        profileStore: store,
        actionExecutor: FakeActionExecutor()
    )
    model.debugSnapshot = DebugSnapshot(
        activePhysicalKeys: ["u7-89-c978"],
        activeLogicalKeys: [],
        candidateRuleIDs: [],
        winningRuleID: nil,
        firedRuleIDs: [],
        pendingSingleRuleIDs: [],
        outputLog: []
    )
    model.pinCurrentPressedCombo()
    model.debugSnapshot = .empty

    #expect(model.pinnedPhysicalRules.count == 1)
    #expect(model.workflowStep == .configureGroup)

    model.clearWorkflowState()

    #expect(model.pinnedPhysicalRules.count == 1)
    #expect(model.selectedRuleID == nil)
    #expect(model.workflowStep == .waitingForKeys)
    #expect(model.primaryNotice.title == "状态已清空")
}

@MainActor
@Test func initDoesNotAutoAdvanceProgressFromLegacyRules() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let store = TestProfileStore(storageURL: directoryURL.appendingPathComponent("profile.json"))

    var profile = DeviceProfile.defaultProfile()
    profile.rules = [
        BindingRule(
            id: "legacy-rule",
            triggerKeys: ["K00", "K01", "K02"],
            triggerType: .combo,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: profile.functionUnits[0].id,
            enabled: true,
            priority: 100
        )
    ]
    try store.saveProfile(profile)

    let model = AppModel(
        inputService: FakeInputDeviceService(),
        profileStore: store,
        actionExecutor: FakeActionExecutor()
    )

    #expect(model.selectedRuleID == nil)
    #expect(model.workflowStep == .waitingForKeys)
}

private struct TestProfileStore: ProfileStore {
    let storageURL: URL

    func loadProfile() throws -> DeviceProfile? {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(DeviceProfile.self, from: Data(contentsOf: storageURL))
    }

    func saveProfile(_ profile: DeviceProfile) throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(profile).write(to: storageURL)
    }
}

private final class FakePermissionChecker: AccessibilityPermissionChecking {
    private let isTrustedValue: Bool

    init(isTrustedValue: Bool) {
        self.isTrustedValue = isTrustedValue
    }

    func isTrusted() -> Bool {
        isTrustedValue
    }

    func prompt() {}
}

private final class FakeShortcutPerformer: ShortcutActionPerforming {
    private(set) var performCount = 0

    func perform(_ shortcut: ShortcutSpec) throws {
        performCount += 1
    }
}

private final class FakeMediaKeyPerformer: MediaKeyActionPerforming {
    private(set) var performCount = 0

    func perform(_ mediaKey: MediaKeyType) throws {
        performCount += 1
    }
}

private final class FakeActionExecutor: ActionExecutor {
    var permissionState: AccessibilityPermissionState = .authorized

    func refreshPermissionState() {}
    func requestAccessibilityPermission() {}

    func execute(functionUnit: FunctionUnit) -> ActionExecutionResult {
        ActionExecutionResult(usedLiveExecution: true, message: "fake execute \(functionUnit.name)")
    }
}

private final class FakeInputDeviceService: InputDeviceService {
    let events: AsyncStream<InputEvent>
    let devicesStream: AsyncStream<[ManagedInputDevice]>

    init() {
        self.events = AsyncStream { continuation in
            continuation.finish()
        }
        self.devicesStream = AsyncStream { continuation in
            continuation.yield([ManagedInputDevice.mockPad])
            continuation.finish()
        }
    }

    func availableDevices() -> [ManagedInputDevice] {
        [ManagedInputDevice.mockPad]
    }

    func setActiveDevice(_ deviceID: String?) {}
    func activeDeviceID() -> String? { ManagedInputDevice.mockPad.id }
    func beginCalibration() {}
    func endCalibration() {}
    func simulatePress(physicalKeyID: String) {}
    func simulateRelease(physicalKeyID: String) {}
}
