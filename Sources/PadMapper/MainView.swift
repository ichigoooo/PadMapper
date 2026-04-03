import SwiftUI

private enum PadTheme {
    static let appBackground = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.985)
    static let card = Color.white
    static let text = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let muted = Color(red: 0.39, green: 0.42, blue: 0.48)
    static let subtle = Color.black.opacity(0.05)
    static let accent = Color(red: 0.13, green: 0.46, blue: 0.95)
}

struct MainView: View {
    @Bindable var model: AppModel

    @State private var showAdvancedSettings = false
    @State private var showCalibration = false
    @State private var showMockPanel = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PadTheme.appBackground)

                Divider()

                inspector
                    .frame(width: 370)
                    .background(PadTheme.panelBackground)
            }
        }
        .background(PadTheme.appBackground)
        .frame(minWidth: 1100, minHeight: 760)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PadMapper")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(PadTheme.text)
                    Text("按住真实按键 -> 固定组合 -> 配功能")
                        .font(.callout)
                        .foregroundStyle(PadTheme.muted)
                }
                Spacer()
                CompactBadge(title: "输入源", value: model.inputSourceMode.title)
                CompactBadge(title: "当前按下", value: model.activePhysicalKeysText)
            }

            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("设备")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PadTheme.text)

                    ForEach(model.devices) { device in
                        DevicePickerRow(device: device, isSelected: device.id == model.activeDeviceID) {
                            model.selectInputDevice(device.id)
                        }
                    }

                    infoRow("快捷键权限", model.permissionState == .authorized ? "已授权" : "未授权")

                    if model.permissionState != .authorized {
                        Button("请求辅助功能权限") {
                            model.requestAccessibilityPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PadTheme.accent)
                    }

                    DisclosureGroup(isExpanded: $showCalibration) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这是二级兼容入口，主流程通常不需要。")
                                .font(.caption)
                                .foregroundStyle(PadTheme.muted)

                            Picker("逻辑键", selection: Binding(
                                get: { model.selectedCalibrationKeyID ?? model.profile.layout.first?.id ?? "" },
                                set: { model.setCalibrationTargetKey($0) }
                            )) {
                                ForEach(model.profile.layout.sorted(by: layoutSort)) { key in
                                    Text("\(key.label) (\(key.id))").tag(key.id)
                                }
                            }
                            .labelsHidden()

                            if model.isCalibrationMode {
                                Button("取消校准") {
                                    model.cancelCalibration()
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("开始校准所选逻辑键") {
                                    model.beginCalibrationForSelectedKey()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!model.canCalibrateSelectedKey)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("校准（可选）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PadTheme.text)
                    }

                    Text(model.statusMessage)
                        .font(.callout)
                        .foregroundStyle(PadTheme.muted)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(PadTheme.subtle)
                        )
                }
                .padding(.top, 8)
            } label: {
                Text("更多设置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
            }
        }
        .padding(20)
        .background(PadTheme.card)
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "1. 按下组合并固定", subtitle: "在真实小键盘上按住若干键，确认按键码后点击固定。") {
                    VStack(alignment: .leading, spacing: 12) {
                        ValueCard(title: "当前按下的物理键码", value: model.activePhysicalKeysText)

                        Button("固定当前按键组合") {
                            model.pinCurrentPressedCombo()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PadTheme.accent)
                        .disabled(!model.canPinCurrentPressedCombo)
                    }
                }

                SectionCard(title: "2. 已固定组合", subtitle: "点击任意一项，在右侧配置它的动作。") {
                    if model.pinnedPhysicalRules.isEmpty {
                        SimpleHint(text: "还没有组合。先在真实设备上按住按键，再点击“固定当前按键组合”。")
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.pinnedPhysicalRules) { rule in
                                ComboRow(
                                    comboText: rule.triggerKeys.joined(separator: " + "),
                                    actionText: actionSummary(for: rule),
                                    isSelected: rule.id == model.selectedRuleID
                                ) {
                                    model.selectRule(rule.id)
                                }
                            }
                        }
                    }

                    if model.selectedRule != nil {
                        Button("删除当前组合") {
                            model.deleteSelectedRule()
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }

                DisclosureGroup(isExpanded: $showMockPanel) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(model.profile.layout.sorted(by: layoutSort)) { key in
                            PhysicalTestKeyButton(title: key.defaultPhysicalKeyID, color: key.colorToken.color) {
                                model.simulatePress(key.defaultPhysicalKeyID)
                            } onRelease: {
                                model.simulateRelease(key.defaultPhysicalKeyID)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Text("测试模式按键面板（可选）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(PadTheme.card)
                )
            }
            .padding(22)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "3. 给组合配置功能", subtitle: "支持快捷键和多媒体键。") {
                    if let rule = model.selectedRule, let unit = model.selectedRuleFunctionUnit {
                        VStack(alignment: .leading, spacing: 12) {
                            ValueCard(title: "当前组合", value: rule.triggerKeys.joined(separator: " + "))

                            TextField("功能名称", text: Binding(
                                get: { unit.name },
                                set: { model.updateFunctionUnitName($0) }
                            ))
                            .textFieldStyle(.roundedBorder)

                            Picker("动作类型", selection: Binding(
                                get: { model.selectedActionType },
                                set: { model.updateSelectedActionType($0) }
                            )) {
                                Text("快捷键").tag(OutputActionType.shortcut)
                                Text("多媒体键").tag(OutputActionType.mediaKey)
                            }
                            .pickerStyle(.segmented)

                            if model.selectedActionType == .shortcut {
                                TextField("按键，例如 y / space / return", text: Binding(
                                    get: { model.selectedShortcutSpec?.key ?? "" },
                                    set: { model.updateFunctionUnitShortcutKey($0) }
                                ))
                                .textFieldStyle(.roundedBorder)

                                HStack(spacing: 8) {
                                    ForEach(ShortcutModifier.allCases) { modifier in
                                        let enabled = model.selectedShortcutSpec?.modifiers.contains(modifier) ?? false
                                        Toggle(modifier.title, isOn: Binding(
                                            get: { enabled },
                                            set: { model.updateFunctionUnitModifier(modifier, enabled: $0) }
                                        ))
                                        .toggleStyle(.button)
                                    }
                                }
                            } else {
                                Picker("多媒体键", selection: Binding(
                                    get: { model.selectedMediaKey },
                                    set: { model.updateSelectedMediaKey($0) }
                                )) {
                                    ForEach(MediaKeyType.allCases) { mediaKey in
                                        Text(mediaKey.title).tag(mediaKey)
                                    }
                                }
                                .labelsHidden()
                            }
                        }
                    } else {
                        SimpleHint(text: "先在左侧固定一个组合，再来配置动作。")
                    }
                }

                SectionCard(title: "运行反馈", subtitle: "用于确认规则是否命中和动作是否发出。") {
                    ValueCard(title: "命中的规则", value: model.debugSnapshot.winningRuleID ?? "无")
                    ValueCard(title: "当前按下的物理键", value: model.activePhysicalKeysText)

                    if model.debugSnapshot.outputLog.isEmpty {
                        SimpleHint(text: "暂无输出日志")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(model.debugSnapshot.outputLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(PadTheme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(PadTheme.subtle)
                        )
                    }
                }
            }
            .padding(18)
        }
    }

    private func actionSummary(for rule: BindingRule) -> String {
        guard let unit = model.profile.functionUnits.first(where: { $0.id == rule.functionUnitId }),
              let action = unit.actions.first else {
            return "未绑定动作"
        }
        switch action.type {
        case .shortcut:
            guard let shortcut = action.shortcut else { return "快捷键未配置" }
            return KeyCodeMapper.render(shortcut: shortcut)
        case .mediaKey:
            return action.mediaKey?.title ?? "多媒体键未配置"
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.muted)
            Text(value)
                .font(.callout)
                .foregroundStyle(PadTheme.text)
        }
    }

    private func layoutSort(lhs: LayoutKey, rhs: LayoutKey) -> Bool {
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.col < rhs.col
    }
}

private struct CompactBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.muted)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(PadTheme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.subtle)
        )
    }
}

private struct DevicePickerRow: View {
    let device: ManagedInputDevice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(device.statusText)
                        .font(.caption)
                        .foregroundStyle(PadTheme.muted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PadTheme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? PadTheme.accent.opacity(0.12) : PadTheme.subtle)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PadTheme.text)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(PadTheme.muted)
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(PadTheme.card)
        )
    }
}

private struct ValueCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.muted)
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(PadTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(PadTheme.subtle)
        )
    }
}

private struct SimpleHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(PadTheme.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PadTheme.subtle)
            )
    }
}

private struct ComboRow: View {
    let comboText: String
    let actionText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(comboText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(actionText)
                        .font(.caption)
                        .foregroundStyle(PadTheme.muted)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(PadTheme.accent)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? PadTheme.accent.opacity(0.12) : PadTheme.subtle)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PhysicalTestKeyButton: View {
    let title: String
    let color: Color
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(PadTheme.text)
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(color.opacity(isPressed ? 0.96 : 0.76))
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            .animation(.easeOut(duration: 0.12), value: isPressed)
    }
}
