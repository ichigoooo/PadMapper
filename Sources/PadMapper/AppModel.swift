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

    @ObservationIgnored private let inputService: InputDeviceService
    @ObservationIgnored private let profileStore: ProfileStore
    @ObservationIgnored private let actionExecutor: ActionExecutor
    @ObservationIgnored private let resolver = ComboResolver()
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var flushTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var ignoredCalibrationPhysicalKeys: Set<String> = []
    @ObservationIgnored private var lastUnmappedNoticeAt: Date?

    static func bootstrap() -> AppModel {
        let inputService = IOHIDInputDeviceService()
        let store = JSONProfileStore()
        let executor = CompositeActionExecutor()
        return AppModel(inputService: inputService, profileStore: store, actionExecutor: executor)
    }

    init(inputService: InputDeviceService, profileStore: ProfileStore, actionExecutor: ActionExecutor) {
        let loadedProfile = (try? profileStore.loadProfile()) ?? DeviceProfile.defaultProfile()
        let initialRule = loadedProfile.rules.first(where: { $0.triggerInputMode == .physical }) ?? loadedProfile.rules.first
        self.inputService = inputService
        self.profileStore = profileStore
        self.actionExecutor = actionExecutor
        self.devices = inputService.availableDevices()
        self.activeDeviceID = inputService.activeDeviceID()
        self.inputSourceMode = .none
        self.profile = loadedProfile
        self.selectedKeyIDs = []
        self.selectedFunctionUnitID = initialRule?.functionUnitId ?? loadedProfile.functionUnits.first?.id
        self.selectedRuleID = initialRule?.id
        self.awaitingCalibrationKeyID = nil
        self.isCalibrationMode = false
        self.statusMessage = "按住小键盘上的若干键后，点击“固定当前按键组合”即可创建规则。"
        self.debugSnapshot = .empty

        restorePreferredDeviceIfNeeded(from: devices, announce: false)
        startEventLoop()
        startDevicesLoop()
    }

    deinit {
        eventTask?.cancel()
        devicesTask?.cancel()
        flushTasks.values.forEach { $0.cancel() }
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

    var selectedKeysSummaryText: String {
        let keys = orderedSelectedKeys
        guard !keys.isEmpty else {
            return "还没选中逻辑键。先点彩色方块，再创建规则；如果要做真实映射，可在“更多设置”里校准当前选中的单个键。"
        }

        if keys.count == 1, let key = keys.first {
            let bindingText = key.calibrateBinding?.physicalKeyID ?? "未校准"
            return "当前选中 1 个键：\(key.label)。当前绑定：\(bindingText)。"
        }

        return "当前选中 \(keys.count) 个键：\(keys.map(\.label).joined(separator: " + "))。现在可以直接创建一个多键组合规则。"
    }

    func refreshPermissionState() {
        actionExecutor.refreshPermissionState()
    }

    func requestAccessibilityPermission() {
        actionExecutor.requestAccessibilityPermission()
        statusMessage = "已请求打开辅助功能授权提示。"
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
        statusMessage = device.isMock ? "已切换到测试模式。" : "已选择真实设备：\(device.name)。当前为监听模式。"
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
        statusMessage = "正在校准 \(key.label)。请在\(activeDevice.isMock ? "测试区" : "真实设备")上按下目标物理键。"
    }

    func cancelCalibration() {
        awaitingCalibrationKeyID = nil
        isCalibrationMode = false
        inputService.endCalibration()
        statusMessage = "已取消校准。"
    }

    func setCalibrationTargetKey(_ keyID: String?) {
        selectedKeyIDs = keyID.map { [$0] } ?? []
    }

    func pinCurrentPressedCombo() {
        let triggerKeys = normalizedPhysicalKeys(debugSnapshot.activePhysicalKeys)
        guard !triggerKeys.isEmpty else {
            statusMessage = "先在小键盘上按住至少 1 个键，再点“固定当前按键组合”。"
            return
        }

        if let existing = profile.rules.first(where: { rule in
            rule.triggerInputMode == .physical && normalizedPhysicalKeys(rule.triggerKeys) == triggerKeys
        }) {
            selectRule(existing.id)
            statusMessage = "这个组合已经存在，已帮你定位到它。"
            return
        }

        let functionUnit = FunctionUnit(
            id: UUID().uuidString,
            name: "组合 \(pinnedPhysicalRules.count + 1)",
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
        statusMessage = "已固定组合：\(triggerKeys.joined(separator: " + "))。现在可以配置它的功能。"
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
        statusMessage = "已创建\(dedupedKeys.count == 1 ? "单键" : "多键组合")规则。"
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
            statusMessage = "示例三键组合已经存在。按 P00 + P01 + P02 就能试。"
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
        statusMessage = "已创建示例三键组合。现在可以在测试区或真实设备上触发它。"
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
        statusMessage = "已删除当前组合。"
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
                statusMessage = "之前选择的真实设备已断开连接。你可以重新选择它，或先切回测试模式。"
            }
        }

        let hadActiveBeforeRestore = activeDeviceID
        restorePreferredDeviceIfNeeded(from: updatedDevices, announce: false)

        if hadActiveBeforeRestore != activeDeviceID, let activeDevice, !activeDevice.isMock {
            statusMessage = "已切到真实设备：\(activeDevice.name)。现在按住几个键后点“固定当前按键组合”即可。"
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
                statusMessage = "已自动恢复目标设备：\(matchedDevice.name)。"
            }
            return
        }

        // UX fallback: if profile was still mock, prefer the first real keyboard automatically.
        if let firstRealDevice = updatedDevices.first(where: { !$0.isMock }) {
            inputService.setActiveDevice(firstRealDevice.id)
            activeDeviceID = firstRealDevice.id
            inputSourceMode = .hid
            if announce {
                statusMessage = "已自动切换到真实设备：\(firstRealDevice.name)。如需回退，可在“更多设置”切回测试模式。"
            }
            return
        }

        if updatedDevices.contains(where: { $0.id == ManagedInputDevice.mockPad.id }) {
            inputService.setActiveDevice(ManagedInputDevice.mockPad.id)
            activeDeviceID = ManagedInputDevice.mockPad.id
            inputSourceMode = .mock
            if announce {
                statusMessage = "已切回测试模式。"
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
        maybeNotifyUncalibratedInput(for: event)
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
            statusMessage = result.message
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
        statusMessage = "已将 \(logicalKeyID) 绑定到 \(physicalKeyID)。"
        return true
    }

    private func maybeNotifyUncalibratedInput(for event: InputEvent) {
        guard inputSourceMode == .hid, event.isPressed else { return }
        let now = Date()
        if let last = lastUnmappedNoticeAt, now.timeIntervalSince(last) < 1.2 {
            return
        }
        lastUnmappedNoticeAt = now
        statusMessage = "已识别到按键码 \(event.physicalKeyID)。保持按住后点“固定当前按键组合”即可保存。"
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
            statusMessage = "保存失败：\(error.localizedDescription)"
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
