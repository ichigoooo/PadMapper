import SwiftUI

private enum PadTheme {
    static let appBackground = Color(red: 0.945, green: 0.952, blue: 0.968)
    static let topBackground = Color(red: 0.972, green: 0.976, blue: 0.988)
    static let surface = Color.white
    static let panelSurface = Color(red: 0.985, green: 0.988, blue: 0.994)
    static let border = Color.black.opacity(0.08)
    static let strongBorder = Color.black.opacity(0.12)
    static let subtleFill = Color.black.opacity(0.035)
    static let mutedFill = Color.black.opacity(0.05)
    static let accent = Color(red: 0.12, green: 0.45, blue: 0.92)
    static let accentSoft = Color(red: 0.92, green: 0.96, blue: 1.0)
    static let success = Color(red: 0.18, green: 0.55, blue: 0.31)
    static let successSoft = Color(red: 0.93, green: 0.98, blue: 0.94)
    static let warning = Color(red: 0.73, green: 0.47, blue: 0.10)
    static let warningSoft = Color(red: 0.995, green: 0.96, blue: 0.89)
    static let danger = Color(red: 0.74, green: 0.22, blue: 0.20)
    static let dangerSoft = Color(red: 0.995, green: 0.93, blue: 0.93)
    static let text = Color(red: 0.10, green: 0.12, blue: 0.16)
    static let secondaryText = Color(red: 0.33, green: 0.37, blue: 0.43)
    static let tertiaryText = Color(red: 0.49, green: 0.53, blue: 0.59)
}

struct MainView: View {
    private enum ConfigField: Hashable {
        case name
        case shortcut
    }

    @Bindable var model: AppModel

    @State private var showAdvancedSettings = false
    @State private var showCalibration = false
    @State private var draftFunctionName = ""
    @State private var draftShortcutKey = ""
    @State private var draftActionType: OutputActionType = .shortcut
    @State private var draftMediaKey: MediaKeyType = .playPause
    @State private var draftModifiers: Set<ShortcutModifier> = []
    @FocusState private var focusedField: ConfigField?

    private var reversedFeedbackEntries: [RuntimeFeedbackEntry] {
        Array(model.feedbackEntries.reversed())
    }

    private var selectedPhysicalRule: BindingRule? {
        guard let rule = model.selectedRule, rule.triggerInputMode == .physical else { return nil }
        return rule
    }

    private var prominentNotice: PrimaryNotice? {
        let notice = model.primaryNotice
        if notice.title == "开始使用" {
            return nil
        }

        let visibleTitles: Set<String> = [
            "还没有按键",
            "按键组已存在",
            "按键组冲突",
            "已固定按键组",
            "已保存按键组配置",
            "状态已清空"
        ]

        if notice.level == .error || notice.level == .warning {
            return notice
        }

        if visibleTitles.contains(notice.title) {
            return notice
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                workspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                inspector
                    .frame(width: 374)
                    .background(PadTheme.panelSurface)
            }
        }
        .frame(minWidth: 1160, minHeight: 820)
        .background(PadTheme.appBackground)
        .onAppear {
            syncDraftsFromSelection()
        }
        .onChange(of: model.selectedRuleID) { _, _ in
            focusedField = nil
            syncDraftsFromSelection()
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PadMapper")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PadTheme.text)

                    Text("把多个键归为同一组；组内任意一个键按下都会触发，短时间内多个键只算一次。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(PadTheme.secondaryText)
                }

                Spacer(minLength: 20)

                HStack(spacing: 10) {
                    StatusBadge(title: "输入源", value: model.inputSourceMode.title)

                    Button("最小化到托盘") {
                        NotificationCenter.default.post(name: .padMapperHideToTrayRequested, object: nil)
                    }
                    .buttonStyle(PadButtonStyle(kind: .primary))
                    .disabled(model.pinnedPhysicalRules.isEmpty)
                }
            }

            ProgressHeader(step: model.workflowStep) {
                model.clearWorkflowState()
                syncDraftsFromSelection()
            }

            VStack(alignment: .leading, spacing: 8) {
                if model.shouldShowPermissionReminder {
                    HeaderHintRow(
                        iconName: "lock.open.display",
                        title: "快捷键权限尚未开启",
                        message: "没有辅助功能权限时，动作会先以日志方式记录。"
                    )
                }

                if model.shouldShowMockReminder {
                    HeaderHintRow(
                        iconName: "keyboard.badge.ellipsis",
                        title: "当前是测试模式",
                        message: "还没有接入真实设备时，也可以先完成按键组和动作配置。"
                    )
                }
            }

            DisclosureGroup(isExpanded: $showAdvancedSettings) {
                VStack(alignment: .leading, spacing: 14) {
                    InspectorSubsection(title: "输入设备") {
                        VStack(spacing: 10) {
                            ForEach(model.devices) { device in
                                DevicePickerRow(device: device, isSelected: device.id == model.activeDeviceID) {
                                    model.selectInputDevice(device.id)
                                }
                            }
                        }
                    }

                    InspectorSubsection(title: "系统权限") {
                        VStack(alignment: .leading, spacing: 10) {
                            CompactInfoRow(title: "快捷键权限", value: model.permissionState.title)

                            if model.permissionState != .authorized {
                                Button("请求辅助功能权限") {
                                    model.requestAccessibilityPermission()
                                }
                                .buttonStyle(PadButtonStyle(kind: .secondary))
                            }
                        }
                    }

                    DisclosureGroup(isExpanded: $showCalibration) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("这是兼容入口。主流程通常不需要手动校准。")
                                .font(.caption)
                                .foregroundStyle(PadTheme.tertiaryText)

                            Picker("逻辑键", selection: Binding(
                                get: { model.selectedCalibrationKeyID ?? model.profile.layout.first?.id ?? "" },
                                set: { model.setCalibrationTargetKey($0) }
                            )) {
                                ForEach(model.profile.layout.sorted(by: layoutSort)) { key in
                                    Text("\(key.label) (\(key.id))").tag(key.id)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)

                            if model.isCalibrationMode {
                                Button("取消校准") {
                                    model.cancelCalibration()
                                }
                                .buttonStyle(PadButtonStyle(kind: .secondary))
                            } else {
                                Button("开始校准所选逻辑键") {
                                    model.beginCalibrationForSelectedKey()
                                }
                                .buttonStyle(PadButtonStyle(kind: .secondary))
                                .disabled(!model.canCalibrateSelectedKey)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("校准（可选）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(PadTheme.secondaryText)
                    }
                }
                .padding(.top, 10)
            } label: {
                Text("更多设置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
            }
            .tint(PadTheme.secondaryText)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(PadTheme.topBackground)
    }

    private var workspace: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                WorkflowPanel(
                    index: "1",
                    title: "识别当前按键组",
                    subtitle: "先按下想归为同一组的键，再点击固定。键码只作为确认信息。"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        InsetCodeBlock(title: "当前按下的物理键码", value: model.activePhysicalKeysText)

                        HStack(spacing: 12) {
                            Button("固定当前按键组") {
                                model.pinCurrentPressedCombo()
                            }
                            .buttonStyle(PadButtonStyle(kind: .primary))
                            .disabled(!model.canPinCurrentPressedCombo)

                            Spacer(minLength: 0)
                        }

                        if let notice = prominentNotice {
                            InlineNotice(notice: notice)
                        }
                    }
                }

                WorkflowPanel(
                    index: "2",
                    title: "已固定按键组",
                    subtitle: "每一项都是一组等价触发键。点选后在右侧继续配置动作。"
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.pinnedPhysicalRules.isEmpty {
                            EmptyStateCard(
                                title: "还没有按键组",
                                message: "先按下想归为一组的键，再点击“固定当前按键组”。",
                                footnote: "保存后，右侧会自动进入动作配置。"
                            )
                        } else {
                            VStack(spacing: 8) {
                                ForEach(model.pinnedPhysicalRules) { rule in
                                    ComboRow(
                                        title: comboTitle(for: rule),
                                        subtitle: rule.triggerKeys.joined(separator: " + "),
                                        actionText: actionSummary(for: rule),
                                        isSelected: rule.id == model.selectedRuleID
                                    ) {
                                        model.selectRule(rule.id)
                                    }
                                }
                            }
                        }

                        if model.selectedRule != nil {
                            Button("删除当前按键组") {
                                model.deleteSelectedRule()
                            }
                            .buttonStyle(PadButtonStyle(kind: .danger))
                        }
                    }
                }
            }
            .padding(22)
        }
        .background(PadTheme.appBackground)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorPanel(title: "按键组检查器", subtitle: "在这里确认名称、动作类型和最近反馈。") {
                    VStack(alignment: .leading, spacing: 18) {
                        if let rule = selectedPhysicalRule {
                            selectedGroupSummary(rule)

                            Divider()

                            configurationForm

                            Divider()

                            feedbackSection
                        } else {
                            EmptyInspectorState()

                            Divider()

                            feedbackSection
                        }
                    }
                }
            }
            .padding(18)
        }
    }

    @ViewBuilder
    private func selectedGroupSummary(_ rule: BindingRule) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前选中")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)

            VStack(alignment: .leading, spacing: 10) {
                SummaryRow(title: "名称", value: model.selectedRuleDisplayName)
                SummaryRow(title: "触发键码", value: rule.triggerKeys.joined(separator: " + "))
                SummaryRow(title: "当前动作", value: model.currentActionSummaryText)
            }
        }
    }

    private var configurationForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("配置动作")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PadTheme.text)

            LabeledField(title: "按键组名称") {
                StyledTextField("例如：复制组", text: $draftFunctionName)
                    .focused($focusedField, equals: .name)
            }

            LabeledField(title: "动作类型") {
                Picker("动作类型", selection: $draftActionType) {
                    Text("快捷键").tag(OutputActionType.shortcut)
                    Text("多媒体键").tag(OutputActionType.mediaKey)
                }
                .pickerStyle(.segmented)
            }

            if draftActionType == .shortcut {
                LabeledField(title: "快捷键") {
                    StyledTextField("例如：y / space / return", text: $draftShortcutKey)
                        .focused($focusedField, equals: .shortcut)
                }

                LabeledField(title: "修饰键") {
                    HStack(spacing: 8) {
                        ForEach(ShortcutModifier.allCases) { modifier in
                            Button(modifier.title) {
                                if draftModifiers.contains(modifier) {
                                    draftModifiers.remove(modifier)
                                } else {
                                    draftModifiers.insert(modifier)
                                }
                            }
                            .buttonStyle(
                                ModifierButtonStyle(isSelected: draftModifiers.contains(modifier))
                            )
                        }
                    }
                }
            } else {
                LabeledField(title: "多媒体键") {
                    Menu {
                        ForEach(MediaKeyType.allCases) { mediaKey in
                            Button(mediaKey.title) {
                                draftMediaKey = mediaKey
                            }
                        }
                    } label: {
                        HStack {
                            Text(draftMediaKey.title)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(PadTheme.tertiaryText)
                        }
                    }
                    .buttonStyle(FieldMenuButtonStyle())
                }
            }

            HStack {
                Button("确认配置") {
                    commitDraftsAndUnfocus()
                }
                .buttonStyle(PadButtonStyle(kind: .primary))

                Spacer(minLength: 0)
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("运行反馈")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PadTheme.text)

            VStack(spacing: 10) {
                CompactInfoRow(title: "命中的规则", value: model.debugSnapshot.winningRuleID ?? "无")
                CompactInfoRow(title: "当前按下的物理键", value: model.activePhysicalKeysText)
            }

            if reversedFeedbackEntries.isEmpty {
                QuietPlaceholder(text: "暂时还没有消息。保存一个按键组后，按下组内任意键即可在这里看到反馈。")
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(reversedFeedbackEntries.enumerated()), id: \.element.id) { index, entry in
                        FeedbackRow(entry: entry, isLatest: index == 0)
                    }
                }
            }
        }
    }

    private func actionSummary(for rule: BindingRule) -> String {
        guard let unit = model.profile.functionUnits.first(where: { $0.id == rule.functionUnitId }),
              let action = unit.actions.first else {
            return "未绑定动作"
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

    private func comboTitle(for rule: BindingRule) -> String {
        model.profile.functionUnits.first(where: { $0.id == rule.functionUnitId })?.name.nilIfEmpty ?? "未命名按键组"
    }

    private func layoutSort(lhs: LayoutKey, rhs: LayoutKey) -> Bool {
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.col < rhs.col
    }

    private func syncDraftsFromSelection() {
        draftFunctionName = model.selectedRuleFunctionUnit?.name ?? ""
        draftShortcutKey = model.selectedShortcutSpec?.key ?? ""
        draftActionType = model.selectedActionType
        draftMediaKey = model.selectedMediaKey
        draftModifiers = Set(model.selectedShortcutSpec?.modifiers ?? [])
    }

    private func commitDraftsAndUnfocus() {
        model.confirmSelectedGroupConfiguration(
            name: draftFunctionName,
            actionType: draftActionType,
            shortcutKey: draftShortcutKey,
            modifiers: Array(draftModifiers),
            mediaKey: draftMediaKey
        )
        syncDraftsFromSelection()
        focusedField = nil
    }
}

private struct ProgressHeader: View {
    let step: WorkflowStep
    let onClear: () -> Void

    private let steps: [WorkflowStep] = [.waitingForKeys, .readyToPin, .configureGroup]

    private func stepState(for item: WorkflowStep) -> StepVisualState {
        guard let currentIndex = steps.firstIndex(of: step),
              let itemIndex = steps.firstIndex(of: item) else {
            return .upcoming
        }

        if itemIndex < currentIndex {
            return .complete
        }
        if itemIndex == currentIndex {
            return .active
        }
        return .upcoming
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("三步流程")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
                Spacer()
                Button("清空状态", action: onClear)
                    .buttonStyle(PadButtonStyle(kind: .secondary, size: .compact))
            }

            HStack(spacing: 12) {
                ForEach(Array(steps.enumerated()), id: \.element.rawValue) { index, item in
                    ProgressStep(
                        index: index + 1,
                        title: item.title,
                        subtitle: subtitle(for: item),
                        state: stepState(for: item)
                    )
                }
            }
        }
    }

    private func subtitle(for step: WorkflowStep) -> String {
        switch step {
        case .waitingForKeys:
            return "按下想归组的键"
        case .readyToPin:
            return "固定当前按键组"
        case .configureGroup:
            return "确认名称和动作"
        }
    }
}

private enum StepVisualState: Equatable {
    case complete
    case active
    case upcoming

    var fill: Color {
        switch self {
        case .complete:
            return PadTheme.success
        case .active:
            return PadTheme.accent
        case .upcoming:
            return PadTheme.mutedFill
        }
    }

    var text: String {
        switch self {
        case .complete:
            return "已完成"
        case .active:
            return "当前步骤"
        case .upcoming:
            return "下一步"
        }
    }

    var textColor: Color {
        switch self {
        case .complete:
            return PadTheme.success
        case .active:
            return PadTheme.accent
        case .upcoming:
            return PadTheme.tertiaryText
        }
    }
}

private struct ProgressStep: View {
    let index: Int
    let title: String
    let subtitle: String
    let state: StepVisualState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(state.fill)
                .frame(height: 6)

            HStack(alignment: .top, spacing: 10) {
                Text("\(index)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(state.textColor)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(state.fill.opacity(state == .upcoming ? 0.65 : 0.16))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PadTheme.secondaryText)
                    Text(state.text)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(state.textColor)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PadTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(state == .active ? PadTheme.accent.opacity(0.22) : PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct HeaderHintRow: View {
    let iconName: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(PadTheme.secondaryText)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(PadTheme.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private enum NoticeTone {
    case info
    case success
    case warning
    case error

    init(level: NoticeLevel) {
        switch level {
        case .info:
            self = .info
        case .success:
            self = .success
        case .warning:
            self = .warning
        case .error:
            self = .error
        }
    }

    var foreground: Color {
        switch self {
        case .info:
            return PadTheme.accent
        case .success:
            return PadTheme.success
        case .warning:
            return PadTheme.warning
        case .error:
            return PadTheme.danger
        }
    }

    var background: Color {
        switch self {
        case .info:
            return PadTheme.accentSoft
        case .success:
            return PadTheme.successSoft
        case .warning:
            return PadTheme.warningSoft
        case .error:
            return PadTheme.dangerSoft
        }
    }

    var iconName: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

private struct StatusBadge: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(PadTheme.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.surface)
                .stroke(PadTheme.border, lineWidth: 1)
        )
    }
}

private struct WorkflowPanel<Content: View>: View {
    let index: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(index)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(PadTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(PadTheme.accentSoft)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(PadTheme.text)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(PadTheme.secondaryText)
                }
            }

            content
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(PadTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 16, y: 8)
        )
    }
}

private struct InspectorPanel<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PadTheme.text)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(PadTheme.secondaryText)
            }

            content
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(PadTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct InspectorSubsection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)
            content
        }
    }
}

private struct InsetCodeBlock: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(PadTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct InlineNotice: View {
    let notice: PrimaryNotice

    var body: some View {
        let tone = NoticeTone(level: notice.level)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(PadTheme.secondaryText)
                if let details = notice.details?.nilIfEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(PadTheme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(tone.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tone.foreground.opacity(0.22), lineWidth: 1)
                )
        )
    }
}

private struct SummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)
            Text(value)
                .font(value.contains("+") ? .system(.callout, design: .monospaced) : .callout)
                .foregroundStyle(PadTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct CompactInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.tertiaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(PadTheme.text)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct LabeledField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PadTheme.secondaryText)
            content
        }
    }
}

private struct StyledTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.callout)
            .foregroundStyle(PadTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PadTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PadTheme.strongBorder, lineWidth: 1)
                    )
            )
    }
}

private struct EmptyStateCard: View {
    let title: String
    let message: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(PadTheme.text)
            Text(message)
                .font(.callout)
                .foregroundStyle(PadTheme.secondaryText)
            Text(footnote)
                .font(.caption)
                .foregroundStyle(PadTheme.tertiaryText)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct EmptyInspectorState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("还没有选中按键组")
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(PadTheme.text)
            Text("先在左侧固定一个按键组，再到这里确认名称和动作。")
                .font(.callout)
                .foregroundStyle(PadTheme.secondaryText)
            Text("当你选中某个按键组后，这里会显示它的键码摘要、动作配置和最近反馈。")
                .font(.caption)
                .foregroundStyle(PadTheme.tertiaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct QuietPlaceholder: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(PadTheme.secondaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct ComboRow: View {
    let title: String
    let subtitle: String
    let actionText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(subtitle)
                        .font(.caption.monospaced())
                        .foregroundStyle(PadTheme.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Text(actionText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? PadTheme.accent : PadTheme.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? PadTheme.accentSoft : PadTheme.subtleFill)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PadTheme.accent)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isSelected ? PadTheme.accentSoft : PadTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isSelected ? PadTheme.accent.opacity(0.28) : PadTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct DevicePickerRow: View {
    let device: ManagedInputDevice
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(device.statusText)
                        .font(.caption)
                        .foregroundStyle(PadTheme.secondaryText)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? PadTheme.accent : PadTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? PadTheme.accentSoft : PadTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? PadTheme.accent.opacity(0.22) : PadTheme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FeedbackRow: View {
    let entry: RuntimeFeedbackEntry
    let isLatest: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(PadTheme.tertiaryText)
                .frame(width: 52, alignment: .leading)

            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(PadTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isLatest ? PadTheme.accentSoft : PadTheme.subtleFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isLatest ? PadTheme.accent.opacity(0.18) : PadTheme.border, lineWidth: 1)
                )
        )
    }
}

private struct PadButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case danger
    }

    enum Size {
        case regular
        case compact

        var minHeight: CGFloat {
            switch self {
            case .regular:
                return 36
            case .compact:
                return 32
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular:
                return 14
            case .compact:
                return 12
            }
        }
    }

    let kind: Kind
    var size: Size = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minHeight: size.minHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(backgroundColor(configuration.isPressed))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: kind == .primary ? 0 : 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.96 : 1)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return PadTheme.text
        case .danger:
            return PadTheme.danger
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return .clear
        case .secondary:
            return PadTheme.border
        case .danger:
            return PadTheme.danger.opacity(0.22)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return isPressed ? PadTheme.accent.opacity(0.88) : PadTheme.accent
        case .secondary:
            return isPressed ? PadTheme.subtleFill.opacity(1.1) : PadTheme.surface
        case .danger:
            return isPressed ? PadTheme.dangerSoft.opacity(0.92) : PadTheme.dangerSoft
        }
    }
}

private struct ModifierButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(isSelected ? .white : PadTheme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isSelected ? PadTheme.accent : PadTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(isSelected ? PadTheme.accent : PadTheme.border, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct FieldMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(PadTheme.text)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(PadTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PadTheme.strongBorder, lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
