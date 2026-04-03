import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    var devices: [ManagedInputDevice]
    var activeDeviceID: String?
    var inputSourceMode: InputSourceMode
    var profile: DeviceProfile
    var selectedKeyIDs: Set<String>
    var selectedFunctionUnitID: String?
    var selectedRuleID: String?
    var awaitingCalibrationKeyID: String?
    var isCalibrationMode: Bool
    var statusMessage: String
    var debugSnapshot: DebugSnapshot
    var feedbackEntries: [RuntimeFeedbackEntry]
    var primaryNotice: PrimaryNotice
    var lastConfigSavedAt: Date?

    @ObservationIgnored private let inputService: InputDeviceService
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let actionExecutor: ActionExecutor
    @ObservationIgnored private let resolver = ComboResolver()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var flushTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var feedbackDismissTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var ignoredCalibrationPhysicalKeys: Set<String> = []

    static func bootstrap() -> AppModel {
        let inputService = IOHIDInputDeviceService()
        let store = JSONProfileStore()
        let executor = CompositeActionExecutor()
        return AppModel(inputService: inputService, profileStore: store, actionExecutor: executor)
    }

    init(inputService: InputDeviceService, profileStore: ProfileStore, actionExecutor: ActionExecutor) {
        let loadedProfile = (try? profileStore.loadProfile()) ?? DeviceProfile.defaultProfile()
        self.inputService = inputService
        self.profileStore = profileStore
        self.actionExecutor = actionExecutor
        self.devices = inputService.availableDevices()
        self.activeDeviceID = inputService.activeDeviceID()
        self.inputSourceMode = .none
        self.profile = loadedProfile
        self.selectedKeyIDs = []
        self.selectedFunctionUnitID = nil
        self.selectedRuleID = nil
        self.awaitingCalibrationKeyID = nil
        self.isCalibrationMode = false
        self.statusMessage = "把多个键归为同一组；组内任意一个键按下都会触发，短时间内多个键只算一次。"
        self.debugSnapshot = .empty
        self.feedbackEntries = []
        self.primaryNotice = PrimaryNotice(
            level: .info,
            title: "开始使用",
            message: "把多个键归为同一组；组内任意一个键按下都会触发，短时间内多个键只算一次。",
            details: "先按键，再固定，最后去右侧确认动作。"
        )
        self.lastConfigSavedAt = nil

        restorePreferredDeviceIfNeeded(from: devices, announce: false)
        startEventLoop()
        startDevicesLoop()
    }

    deinit {
        eventTask?.cancel()
        devicesTask?.cancel()
        flushTasks.values.forEach { $0.cancel() }
        feedbackDismissTasks.values.forEach { $0.cancel() }
    }

    var permissionState: AccessibilityPermissionState {
        actionExecutor.permissionState
    }

    var orderedSelectedKeys: [LayoutKey] {
        profile.layout
            .filter { selectedKeyIDs.contains($0.id) }
            .sorted(by: layoutSort)
    }

    var selectedFunctionUnit: FunctionUnit? {
        guard let selectedFunctionUnitID else { return nil }
        return profile.functionUnits.first(where: { $0.id == selectedFunctionUnitID })
    }

    var selectedRule: BindingRule? {
        guard let selectedRuleID else { return nil }
        return profile.rules.first(where: { $0.id == selectedRuleID })
    }

    var selectedRuleFunctionUnit: FunctionUnit? {
        guard let rule = selectedRule else { return nil }
        return profile.functionUnits.first(where: { $0.id == rule.functionUnitId })
    }

    var activeDevice: ManagedInputDevice? {
        guard let activeDeviceID else { return nil }
        return devices.first(where: { $0.id == activeDeviceID })
    }

    var canCalibrateSelectedKey: Bool {
        orderedSelectedKeys.count == 1 && activeDeviceID != nil
    }

    var selectedCalibrationKeyID: String? {
        orderedSelectedKeys.first?.id
    }

    var pinnedPhysicalRules: [BindingRule] {
        profile.rules
            .filter { $0.triggerInputMode == .physical }
            .sorted(by: ruleSort)
    }

    var activePhysicalKeysText: String {
        debugSnapshot.activePhysicalKeys.joined(separator: " + ").nilIfEmpty ?? "无"
    }

    var canPinCurrentPressedCombo: Bool {
        !debugSnapshot.activePhysicalKeys.isEmpty
    }

    var selectedActionType: OutputActionType {
        selectedRuleFunctionUnit?.actions.first?.type ?? .shortcut
    }

    var selectedShortcutSpec: ShortcutSpec? {
        selectedRuleFunctionUnit?.actions.first?.shortcut
    }

    var selectedMediaKey: MediaKeyType {
        selectedRuleFunctionUnit?.actions.first?.mediaKey ?? .playPause
    }

    var selectedRuleDisplayName: String {
        selectedRuleFunctionUnit?.name.nilIfEmpty ?? "未命名按键组"
    }

    var workflowStep: WorkflowStep {
        if !debugSnapshot.activePhysicalKeys.isEmpty {
            return .readyToPin
        }
        if lastConfigSavedAt != nil {
            return .configureGroup
        }
        if let selectedRule, selectedRule.triggerInputMode == .physical {
            return .configureGroup
        }
        return .waitingForKeys
    }

    var currentActionSummaryText: String {
        guard let action = selectedRuleFunctionUnit?.actions.first else {
            return "还没有配置动作"
        }
        switch action.type {
        case .shortcut:
            guard let shortcut = action.shortcut else {
                return "快捷键未配置"
            }
            return KeyCodeMapper.render(shortcut: shortcut)
        case .mediaKey:
            return action.mediaKey?.title ?? "多媒体键未配置"
        }
    }

    var shouldShowPermissionReminder: Bool {
        permissionState != .authorized
    }

    var shouldShowMockReminder: Bool {
        inputSourceMode == .mock
    }

    var selectedKeysSummaryText: String {
        let keys = orderedSelectedKeys
        guard !keys.isEmpty else {
            return "还没选中逻辑键。先点彩色方块，再创建规则；如果要做真实映射，可在“更多设置”里校准当前选中的单个键。"
        }

        if keys.count == 1, let key = keys.first {
            let bindingText = key.calibrateBinding?.physicalKeyID ?? "未校准"
            return "当前选中 1 个键：\(key.label)。当前绑定：\(bindingText)。"
        }

        return "当前选中 \(keys.count) 个键：\(keys.map(\.label).joined(separator: " + "))。现在可以直接创建一个多键规则。"
    }

    func refreshPermissionState() {
        actionExecutor.refreshPermissionState()
    }

    func requestAccessibilityPermission() {
        actionExecutor.requestAccessibilityPermission()
        presentPrimaryNotice(
            level: .info,
            title: "已请求权限",
            message: "系统已弹出辅助功能授权提示。",
            details: "完成授权后，这些按键组才能真正向系统发出快捷键。"
        )
    }

    func toggleSelection(for keyID: String) {
        if selectedKeyIDs.contains(keyID) {
            selectedKeyIDs.remove(keyID)
        } else {
            selectedKeyIDs.insert(keyID)
        }
    }

    func clearSelection() {
        selectedKeyIDs.removeAll()
    }

    func clearWorkflowState() {
        selectedKeyIDs.removeAll()
        selectedRuleID = nil
        selectedFunctionUnitID = nil
        awaitingCalibrationKeyID = nil
        isCalibrationMode = false
        inputService.endCalibration()
        lastConfigSavedAt = nil
        presentPrimaryNotice(
            level: .info,
            title: "状态已清空",
            message: "当前进度已经重置。",
            details: "现在可以从第一步重新开始：先按键，再固定按键组。"
        )
    }

    func selectInputDevice(_ deviceID: String) {
        guard let device = devices.first(where: { $0.id == deviceID }) else { return }
        inputService.setActiveDevice(device.id)
        activeDeviceID = device.id
        inputSourceMode = device.isMock ? .mock : .hid
        awaitingCalibrationKeyID = nil
        isCalibrationMode = false
        inputService.endCalibration()

        mutateProfile { profile in
            profile.deviceMatch = device.deviceMatch
        }
        if device.isMock {
            presentPrimaryNotice(
                level: .info,
                title: "当前是测试模式",
                message: "还没有使用真实设备输入。",
                details: "你可以先继续配置按键组，之后再切回真实设备验证。"
            )
        } else {
            presentPrimaryNotice(
                level: .success,
                title: "已连接目标设备",
                message: "当前正在监听：\(device.name)。",
                details: "现在可以按下想归组的键，然后固定成按键组。"
            )
        }
    }

    func beginCalibrationForSelectedKey() {
        guard let activeDevice else {
            statusMessage = "请先在“更多设置”里选中一个输入设备。"
            return
        }
        guard let key = orderedSelectedKeys.first, orderedSelectedKeys.count == 1 else {
            statusMessage = "校准前请只选中一个逻辑键。"
            return
        }

        inputService.beginCalibration()
        awaitingCalibrationKeyID = key.id
        isCalibrationMode = true
        presentPrimaryNotice(
            level: .info,
            title: "正在校准",
            message: "请为 \(key.label) 按下目标物理键。",
            details: activeDevice.isMock ? "当前会从测试面板接收按键。" : "当前会从真实设备接收按键。"
        )
    }

    func cancelCalibration() {
        awaitingCalibrationKeyID = nil
        isCalibrationMode = false
        inputService.endCalibration()
        presentPrimaryNotice(
            level: .warning,
            title: "已取消校准",
            message: "当前没有保存新的校准结果。",
            details: nil
        )
    }

    func setCalibrationTargetKey(_ keyID: String?) {
        selectedKeyIDs = keyID.map { [$0] } ?? []
    }

    func pinCurrentPressedCombo() {
        let triggerKeys = normalizedPhysicalKeys(debugSnapshot.activePhysicalKeys)
        guard !triggerKeys.isEmpty else {
            presentPrimaryNotice(
                level: .warning,
                title: "还没有按键",
                message: "请先按下想归组的键，再点击“固定当前按键组”。",
                details: nil,
                alsoLog: true
            )
            return
        }

        if let existing = profile.rules.first(where: { rule in
            rule.triggerInputMode == .physical && normalizedPhysicalKeys(rule.triggerKeys) == triggerKeys
        }) {
            selectRule(existing.id)
            presentPrimaryNotice(
                level: .warning,
                title: "按键组已存在",
                message: "这组按键已经保存过了。",
                details: "我已经帮你定位到现有的按键组。",
                alsoLog: true
            )
            return
        }

        if let conflict = findPinnedRuleConflict(for: triggerKeys) {
            selectRule(conflict.rule.id)
            presentPrimaryNotice(
                level: .error,
                title: "按键组冲突",
                message: "有按键和已有组合冲突，请确认后重新设置。",
                details: "冲突按键：\(conflict.keyID)，已有组合：\(comboDisplayName(for: conflict.rule))。",
                alsoLog: true
            )
            return
        }

        let functionUnit = FunctionUnit(
            id: UUID().uuidString,
            name: "按键组 \(pinnedPhysicalRules.count + 1)",
            description: "由物理键码固定创建",
            actions: [.shortcut(modifiers: [.command], key: "y")],
            enabled: true
        )

        let rule = BindingRule(
            id: UUID().uuidString,
            triggerKeys: triggerKeys,
            triggerType: triggerKeys.count == 1 ? .single : .combo,
            triggerInputMode: .physical,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: functionUnit.id,
            enabled: true,
            priority: 100
        )

        mutateProfile { profile in
            profile.functionUnits.append(functionUnit)
            profile.rules.append(rule)
        }
        selectedFunctionUnitID = functionUnit.id
        selectedRuleID = rule.id
        presentPrimaryNotice(
            level: .success,
            title: "已固定按键组",
            message: "按键组已经保存成功。",
            details: "接下来请在右侧为它设置动作并点击确认。",
            alsoLog: true
        )
    }

    func createRuleFromSelection() {
        let triggerKeys = orderedSelectedKeys.map(\.id)
        guard !triggerKeys.isEmpty else {
            statusMessage = "先在画布里选中 1 个或多个键。"
            return
        }
        guard let functionUnitID = selectedFunctionUnitID ?? profile.functionUnits.first?.id else {
            statusMessage = "请先确保动作区存在一个功能单元。"
            return
        }

        let dedupedKeys = Array(NSOrderedSet(array: triggerKeys)) as? [String] ?? triggerKeys
        let rule = BindingRule(
            id: UUID().uuidString,
            triggerKeys: dedupedKeys,
            triggerType: dedupedKeys.count == 1 ? .single : .combo,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: functionUnitID,
            enabled: true,
            priority: 100
        )

        mutateProfile { profile in
            profile.rules.append(rule)
        }
        selectedRuleID = rule.id
        statusMessage = "已创建\(dedupedKeys.count == 1 ? "单键" : "多键")规则。"
    }

    func createDemoComboRule() {
        guard profile.layout.count >= 3 else { return }
        guard let functionUnitID = selectedFunctionUnitID ?? profile.functionUnits.first?.id else {
            statusMessage = "请先确保动作区存在一个功能单元。"
            return
        }

        let triggerKeys = Array(profile.layout.sorted(by: layoutSort).prefix(3).map(\.id))
        selectedKeyIDs = Set(triggerKeys)

        let existingRule = profile.rules.first(where: {
            $0.functionUnitId == functionUnitID && $0.triggerKeys == triggerKeys
        })
        if let existingRule {
            selectedRuleID = existingRule.id
            statusMessage = "示例三键按键组已经存在。按 P00 + P01 + P02 就能试。"
            return
        }

        let rule = BindingRule(
            id: UUID().uuidString,
            triggerKeys: triggerKeys,
            triggerType: .combo,
            triggerWindowMs: 80,
            suppressIndividualKeys: true,
            functionUnitId: functionUnitID,
            enabled: true,
            priority: 100
        )

        mutateProfile { profile in
            profile.rules.append(rule)
        }
        selectedRuleID = rule.id
        statusMessage = "已创建示例三键按键组。现在可以在测试区或真实设备上触发它。"
    }

    func selectRule(_ id: String) {
        selectedRuleID = id
        if let rule = profile.rules.first(where: { $0.id == id }) {
            if rule.triggerInputMode == .logical {
                selectedKeyIDs = Set(rule.triggerKeys)
            } else {
                selectedKeyIDs = []
            }
            selectedFunctionUnitID = rule.functionUnitId
        }
    }

    func deleteSelectedRule() {
        guard let selectedRuleID else { return }
        guard let deletedRule = profile.rules.first(where: { $0.id == selectedRuleID }) else { return }

        mutateProfile { profile in
            profile.rules.removeAll { $0.id == selectedRuleID }
            let stillUsed = profile.rules.contains(where: { $0.functionUnitId == deletedRule.functionUnitId })
            if !stillUsed {
                profile.functionUnits.removeAll { $0.id == deletedRule.functionUnitId }
            }
        }

        let nextRule = pinnedPhysicalRules.first ?? profile.rules.first
        self.selectedRuleID = nextRule?.id
        self.selectedFunctionUnitID = nextRule?.functionUnitId ?? profile.functionUnits.first?.id
        presentPrimaryNotice(
            level: .warning,
            title: "已删除按键组",
            message: "当前选中的按键组已经移除。",
            details: nil,
            alsoLog: true
        )
    }

    func confirmSelectedGroupConfiguration(
        name: String,
        actionType: OutputActionType,
        shortcutKey: String,
        modifiers: [ShortcutModifier],
        mediaKey: MediaKeyType
    ) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedName = trimmedName.nilIfEmpty ?? "未命名按键组"
        let normalizedShortcutKey = shortcutKey.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "y"

        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            unit.name = normalizedName
            if unit.actions.isEmpty {
                unit.actions = [.shortcut(modifiers: [.command], key: "y")]
            }
            let actionID = unit.actions[0].id
            switch actionType {
            case .shortcut:
                unit.actions[0] = .shortcut(id: actionID, modifiers: modifiers.sorted { $0.rawValue < $1.rawValue }, key: normalizedShortcutKey)
            case .mediaKey:
                unit.actions[0] = .mediaKey(id: actionID, key: mediaKey)
            }
        }

        lastConfigSavedAt = Date()
        presentPrimaryNotice(
            level: .success,
            title: "已保存按键组配置",
            message: "当前按键组的名称和动作已经确认保存。",
            details: "现在可以直接按下组内任意一个键进行测试。",
            alsoLog: true
        )
    }

    func updateFunctionUnitName(_ name: String) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            unit.name = name
        }
    }

    func updateFunctionUnitShortcutKey(_ key: String) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            guard !unit.actions.isEmpty else { return }
            if unit.actions[0].type != .shortcut {
                unit.actions[0] = .shortcut(id: unit.actions[0].id, modifiers: [.command], key: key)
                return
            }
            unit.actions[0].shortcut?.key = key
        }
    }

    func updateFunctionUnitModifier(_ modifier: ShortcutModifier, enabled: Bool) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            guard !unit.actions.isEmpty else { return }
            if unit.actions[0].type != .shortcut {
                unit.actions[0] = .shortcut(id: unit.actions[0].id, modifiers: [], key: "y")
            }
            guard var shortcut = unit.actions[0].shortcut else { return }
            if enabled {
                if !shortcut.modifiers.contains(modifier) {
                    shortcut.modifiers.append(modifier)
                }
            } else {
                shortcut.modifiers.removeAll { $0 == modifier }
            }
            shortcut.modifiers.sort { $0.rawValue < $1.rawValue }
            unit.actions[0].shortcut = shortcut
        }
    }

    func updateSelectedActionType(_ type: OutputActionType) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            guard !unit.actions.isEmpty else { return }
            let actionID = unit.actions[0].id
            switch type {
            case .shortcut:
                let existingKey = unit.actions[0].shortcut?.key ?? "y"
                let existingModifiers = unit.actions[0].shortcut?.modifiers ?? [.command]
                unit.actions[0] = .shortcut(id: actionID, modifiers: existingModifiers, key: existingKey)
            case .mediaKey:
                let existingMedia = unit.actions[0].mediaKey ?? .playPause
                unit.actions[0] = .mediaKey(id: actionID, key: existingMedia)
            }
        }
    }

    func updateSelectedMediaKey(_ mediaKey: MediaKeyType) {
        guard let functionUnitID = selectedRuleFunctionUnit?.id ?? selectedFunctionUnitID else { return }
        mutateFunctionUnit(functionUnitID: functionUnitID) { unit in
            guard !unit.actions.isEmpty else { return }
            if unit.actions[0].type != .mediaKey {
                unit.actions[0] = .mediaKey(id: unit.actions[0].id, key: mediaKey)
                return
            }
            unit.actions[0].mediaKey = mediaKey
        }
    }

    func simulatePress(_ physicalKeyID: String) {
        inputService.simulatePress(physicalKeyID: physicalKeyID)
    }

    func simulateRelease(_ physicalKeyID: String) {
        inputService.simulateRelease(physicalKeyID: physicalKeyID)
    }

    private func startEventLoop() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in inputService.events {
                await self.handle(event: event)
            }
        }
    }

    private func startDevicesLoop() {
        devicesTask?.cancel()
        devicesTask = Task { [weak self] in
            guard let self else { return }
            for await devices in inputService.devicesStream {
                await self.handleDevicesUpdate(devices)
            }
        }
    }

    private func handleDevicesUpdate(_ updatedDevices: [ManagedInputDevice]) async {
        let previousActiveDeviceID = activeDeviceID
        devices = updatedDevices

        if let previousActiveDeviceID, !updatedDevices.contains(where: { $0.id == previousActiveDeviceID }) {
            activeDeviceID = nil
            inputSourceMode = .none
            if previousActiveDeviceID != ManagedInputDevice.mockPad.id {
                presentPrimaryNotice(
                    level: .warning,
                    title: "设备已断开",
                    message: "之前选择的真实设备已经断开。",
                    details: "你可以重新选择它，或先切回测试模式。"
                )
            }
        }

        let hadActiveBeforeRestore = activeDeviceID
        restorePreferredDeviceIfNeeded(from: updatedDevices, announce: false)

        if hadActiveBeforeRestore != activeDeviceID, let activeDevice, !activeDevice.isMock {
            presentPrimaryNotice(
                level: .success,
                title: "已切换到真实设备",
                message: "当前设备：\(activeDevice.name)。",
                details: "现在按下想归组的键，然后点击“固定当前按键组”。"
            )
        }
    }

    private func restorePreferredDeviceIfNeeded(from updatedDevices: [ManagedInputDevice], announce: Bool) {
        if let activeDeviceID,
           updatedDevices.contains(where: { $0.id == activeDeviceID }),
           !(activeDeviceID == ManagedInputDevice.mockPad.id && profile.deviceMatch.transport != "mock" && profile.deviceMatch.transport != nil) {
            inputSourceMode = activeDeviceID == ManagedInputDevice.mockPad.id ? .mock : .hid
            return
        }

        if let matchedDevice = updatedDevices.first(where: { !$0.isMock && profile.deviceMatch.matches(device: $0) }) {
            inputService.setActiveDevice(matchedDevice.id)
            activeDeviceID = matchedDevice.id
            inputSourceMode = .hid
            if announce {
                presentPrimaryNotice(
                    level: .success,
                    title: "已恢复目标设备",
                    message: "当前设备：\(matchedDevice.name)。",
                    details: nil
                )
            }
            return
        }

        // UX fallback: if profile was still mock, prefer the first real keyboard automatically.
        if let firstRealDevice = updatedDevices.first(where: { !$0.isMock }) {
            inputService.setActiveDevice(firstRealDevice.id)
            activeDeviceID = firstRealDevice.id
            inputSourceMode = .hid
            if announce {
                presentPrimaryNotice(
                    level: .success,
                    title: "已自动切换到真实设备",
                    message: "当前设备：\(firstRealDevice.name)。",
                    details: "如需回退，可在“更多设置”切回测试模式。"
                )
            }
            return
        }

        if updatedDevices.contains(where: { $0.id == ManagedInputDevice.mockPad.id }) {
            inputService.setActiveDevice(ManagedInputDevice.mockPad.id)
            activeDeviceID = ManagedInputDevice.mockPad.id
            inputSourceMode = .mock
            if announce {
                presentPrimaryNotice(
                    level: .info,
                    title: "已切回测试模式",
                    message: "当前没有启用真实设备输入。",
                    details: nil
                )
            }
        }
    }

    private func handle(event: InputEvent) async {
        if let awaitingCalibrationKeyID, event.isPressed {
            if bindCalibration(
                logicalKeyID: awaitingCalibrationKeyID,
                physicalKeyID: event.physicalKeyID,
                deviceID: event.deviceID,
                usagePage: event.usagePage,
                usage: event.usage,
                elementCookie: event.elementCookie
            ) {
                ignoredCalibrationPhysicalKeys.insert(event.physicalKeyID)
            }
            self.awaitingCalibrationKeyID = nil
            self.isCalibrationMode = false
            inputService.endCalibration()
            return
        }

        if ignoredCalibrationPhysicalKeys.contains(event.physicalKeyID) {
            if !event.isPressed {
                ignoredCalibrationPhysicalKeys.remove(event.physicalKeyID)
            }
            return
        }

        let outcome = resolver.process(event: event, profile: profile)
        debugSnapshot = outcome.snapshot
        rescheduleFlushTasks()
        perform(matches: outcome.triggeredMatches)
    }

    private func perform(matches: [TriggerMatch]) {
        guard profile.isEnabled else { return }
        for match in matches {
            guard let functionUnit = profile.functionUnits.first(where: { $0.id == match.functionUnitID && $0.enabled }) else {
                continue
            }
            let result = actionExecutor.execute(functionUnit: functionUnit)
            debugSnapshot = resolver.appendLog(result.message)
            presentPrimaryNotice(
                level: result.usedLiveExecution ? .success : .warning,
                title: result.usedLiveExecution ? "已发送动作" : "动作已记录",
                message: result.message,
                details: nil,
                alsoLog: true
            )
        }
    }

    private func rescheduleFlushTasks() {
        flushTasks.values.forEach { $0.cancel() }
        flushTasks.removeAll()

        for (ruleID, deadline) in resolver.pendingSingleRuleDeadlines {
            let interval = max(0, deadline.timeIntervalSinceNow)
            flushTasks[ruleID] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(interval))
                await MainActor.run {
                    guard let self else { return }
                    let outcome = self.resolver.flushPendingSingles(profile: self.profile, now: deadline)
                    self.debugSnapshot = outcome.snapshot
                    self.perform(matches: outcome.triggeredMatches)
                    self.flushTasks.removeValue(forKey: ruleID)
                }
            }
        }
    }

    private func bindCalibration(
        logicalKeyID: String,
        physicalKeyID: String,
        deviceID: String,
        usagePage: Int?,
        usage: Int?,
        elementCookie: String?
    ) -> Bool {
        if let conflictKey = profile.layout.first(where: {
            $0.id != logicalKeyID && $0.calibrateBinding?.deviceId == deviceID && $0.calibrateBinding?.physicalKeyID == physicalKeyID
        }) {
            statusMessage = "绑定失败：\(physicalKeyID) 已被 \(conflictKey.label) 使用。"
            primaryNotice = PrimaryNotice(
                level: .error,
                title: "校准失败",
                message: "这个物理键已经绑定到其他逻辑键。",
                details: "冲突按键：\(physicalKeyID)，已有位置：\(conflictKey.label)。"
            )
            return false
        }

        mutateLayoutKey(keyID: logicalKeyID) { key in
            key.calibrateBinding = PhysicalInputRef(
                deviceId: deviceID,
                physicalKeyID: physicalKeyID,
                usagePage: usagePage,
                usage: usage,
                elementCookie: elementCookie
            )
        }
        presentPrimaryNotice(
            level: .success,
            title: "校准完成",
            message: "已完成逻辑键和物理键的绑定。",
            details: "当前位置：\(logicalKeyID)，物理键：\(physicalKeyID)。"
        )
        return true
    }

    private func mutateFunctionUnit(functionUnitID: String, mutation: (inout FunctionUnit) -> Void) {
        mutateProfile { profile in
            guard let index = profile.functionUnits.firstIndex(where: { $0.id == functionUnitID }) else { return }
            mutation(&profile.functionUnits[index])
        }
    }

    private func mutateLayoutKey(keyID: String, mutation: (inout LayoutKey) -> Void) {
        mutateProfile { profile in
            guard let index = profile.layout.firstIndex(where: { $0.id == keyID }) else { return }
            mutation(&profile.layout[index])
        }
    }

    private func mutateProfile(_ mutation: (inout DeviceProfile) -> Void) {
        var updated = profile
        mutation(&updated)
        profile = updated
        do {
            try profileStore.saveProfile(updated)
        } catch {
            presentPrimaryNotice(
                level: .error,
                title: "保存失败",
                message: "配置没有成功写入本地文件。",
                details: error.localizedDescription,
                alsoLog: true
            )
        }
    }

    private func layoutSort(lhs: LayoutKey, rhs: LayoutKey) -> Bool {
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.col < rhs.col
    }

    private func ruleSort(lhs: BindingRule, rhs: BindingRule) -> Bool {
        if lhs.triggerKeys.count != rhs.triggerKeys.count {
            return lhs.triggerKeys.count > rhs.triggerKeys.count
        }
        if lhs.priority != rhs.priority {
            return lhs.priority > rhs.priority
        }
        return lhs.id < rhs.id
    }

    private func normalizedPhysicalKeys(_ keys: [String]) -> [String] {
        Array(NSOrderedSet(array: keys.sorted())) as? [String] ?? keys.sorted()
    }

    private func findPinnedRuleConflict(for triggerKeys: [String]) -> (rule: BindingRule, keyID: String)? {
        let requestedKeys = Set(triggerKeys)
        for rule in pinnedPhysicalRules {
            let overlappingKeys = normalizedPhysicalKeys(Array(requestedKeys.intersection(rule.triggerKeys)))
            if let keyID = overlappingKeys.first {
                return (rule, keyID)
            }
        }
        return nil
    }

    private func comboDisplayName(for rule: BindingRule) -> String {
        profile.functionUnits
            .first(where: { $0.id == rule.functionUnitId })?
            .name
            .nilIfEmpty ?? "未命名按键组"
    }

    private func presentPrimaryNotice(
        level: NoticeLevel,
        title: String,
        message: String,
        details: String?,
        alsoLog: Bool = false
    ) {
        primaryNotice = PrimaryNotice(level: level, title: title, message: message, details: details)
        statusMessage = primaryNotice.fullText
        if alsoLog {
            appendFeedbackMessage([title, primaryNotice.fullText].joined(separator: " · "))
        }
    }

    private func appendFeedbackMessage(_ message: String) {
        let entry = RuntimeFeedbackEntry(id: UUID().uuidString, timestamp: Date(), message: message)
        feedbackEntries.append(entry)

        feedbackDismissTasks[entry.id]?.cancel()
        feedbackDismissTasks[entry.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            await MainActor.run {
                guard let self else { return }
                self.feedbackEntries.removeAll { $0.id == entry.id }
                self.feedbackDismissTasks.removeValue(forKey: entry.id)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
