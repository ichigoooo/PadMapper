import SwiftUI

private enum PadTheme {
    static let appBackground = Color(red: 0.95, green: 0.96, blue: 0.98)
    static let panelBackground = Color(red: 0.97, green: 0.97, blue: 0.985)
    static let card = Color.white
    static let text = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let muted = Color(red: 0.39, green: 0.42, blue: 0.48)
    static let subtle = Color.black.opacity(0.05)
    static let accent = Color(red: 0.13, green: 0.46, blue: 0.95)
    static let success = Color(red: 0.17, green: 0.58, blue: 0.33)
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
        model.feedbackEntries.reversed()
    }

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
                    .frame(width: 390)
                    .background(PadTheme.panelBackground)
            }
        }
        .background(PadTheme.appBackground)
        .frame(minWidth: 1140, minHeight: 820)
        .onAppear {
            syncDraftsFromSelection()
        }
        .onChange(of: model.selectedRuleID) { _, _ in
            syncDraftsFromSelection()
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PadMapper")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(PadTheme.text)
                    Text("把多个键归为同一组；组内任意一个键按下都会触发，短时间内多个键只算一次。")
                        .font(.callout)
                        .foregroundStyle(PadTheme.muted)
                }

                Spacer()

                CompactBadge(title: "输入源", value: model.inputSourceMode.title)
                Button("最小化到托盘") {
                    NotificationCenter.default.post(name: .padMapperHideToTrayRequested, object: nil)
                }
                .buttonStyle(.borderedProminent)
                .tint(PadTheme.accent)
                .disabled(model.pinnedPhysicalRules.isEmpty)
            }

            ProgressHeader(step: model.workflowStep) {
                model.clearWorkflowState()
                syncDraftsFromSelection()
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
                            Text("这是兼容入口。主流程通常不需要手动校准。")
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

                    NoticeBanner(notice: model.primaryNotice)
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
                if model.shouldShowPermissionReminder || model.shouldShowMockReminder {
                    VStack(spacing: 10) {
                        if model.shouldShowPermissionReminder {
                            ReminderStrip(
                                title: "快捷键还不能真正发送",
                                message: "还没有辅助功能权限。你仍然可以配置按键组，但动作会先以日志方式记录。"
                            )
                        }

                        if model.shouldShowMockReminder {
                            ReminderStrip(
                                title: "当前是测试模式",
                                message: "如果你还没接入真实设备，也可以先完成按键组和动作配置。"
                            )
                        }
                    }
                }

                SectionCard(title: "1. 识别当前按键组", subtitle: "先按下想归为同一组的键，再点击保存。键码只作为辅助确认信息。") {
                    VStack(alignment: .leading, spacing: 12) {
                        ValueCard(title: "当前按下的物理键码", value: model.activePhysicalKeysText)

                        Button("固定当前按键组") {
                            model.pinCurrentPressedCombo()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(PadTheme.accent)
                        .disabled(!model.canPinCurrentPressedCombo)

                        NoticeBanner(notice: model.primaryNotice)
                    }
                }

                SectionCard(title: "2. 已固定按键组", subtitle: "保存后的每一项都是一组等价触发键。点击任意一项，在右侧继续配置动作。") {
                    if model.pinnedPhysicalRules.isEmpty {
                        EmptyStateCard(
                            title: "还没有任何按键组",
                            message: "先在目标设备上按下想归组的键，然后点击“固定当前按键组”。",
                            footnote: "保存成功后，右侧会立即进入动作配置。"
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
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }
            .padding(22)
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "3. 给按键组配置功能", subtitle: "在这里确认名称、动作类型和最终输出。") {
                    if let rule = model.selectedRule {
                        VStack(alignment: .leading, spacing: 12) {
                            ValueCard(title: "按键组名称", value: model.selectedRuleDisplayName)
                            ValueCard(title: "触发键码", value: rule.triggerKeys.joined(separator: " + "))
                            ValueCard(title: "当前动作摘要", value: model.currentActionSummaryText)

                            TextField("按键组名称", text: $draftFunctionName)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .name)

                            Picker("动作类型", selection: $draftActionType) {
                                Text("快捷键").tag(OutputActionType.shortcut)
                                Text("多媒体键").tag(OutputActionType.mediaKey)
                            }
                            .pickerStyle(.segmented)

                            if draftActionType == .shortcut {
                                TextField("按键，例如 y / space / return", text: $draftShortcutKey)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .shortcut)

                                HStack(spacing: 8) {
                                    ForEach(ShortcutModifier.allCases) { modifier in
                                        Toggle(modifier.title, isOn: Binding(
                                            get: { draftModifiers.contains(modifier) },
                                            set: { enabled in
                                                if enabled {
                                                    draftModifiers.insert(modifier)
                                                } else {
                                                    draftModifiers.remove(modifier)
                                                }
                                            }
                                        ))
                                        .toggleStyle(.button)
                                    }
                                }
                            } else {
                                Picker("多媒体键", selection: $draftMediaKey) {
                                    ForEach(MediaKeyType.allCases) { mediaKey in
                                        Text(mediaKey.title).tag(mediaKey)
                                    }
                                }
                                .labelsHidden()
                            }

                            Button("确认配置") {
                                commitDraftsAndUnfocus()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(PadTheme.accent)
                        }
                    } else {
                        EmptyStateCard(
                            title: "还没有选中按键组",
                            message: "先在左侧固定一个按键组，再来配置它的动作。",
                            footnote: "保存后可以立刻按下组内任意一个键进行测试。"
                        )
                    }
                }

                SectionCard(title: "运行反馈", subtitle: "这里会告诉你最近发生了什么，最新消息会排在最前面。") {
                    ValueCard(title: "命中的规则", value: model.debugSnapshot.winningRuleID ?? "无")
                    ValueCard(title: "当前按下的物理键", value: model.activePhysicalKeysText)

                    if reversedFeedbackEntries.isEmpty {
                        SimpleHint(text: "暂时还没有消息。可以先固定一个按键组并测试一次。")
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(reversedFeedbackEntries.enumerated()), id: \.element.id) { index, entry in
                                FeedbackRow(
                                    entry: entry,
                                    isLatest: index == 0
                                )
                            }
                        }
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

    private func comboTitle(for rule: BindingRule) -> String {
        model.profile.functionUnits.first(where: { $0.id == rule.functionUnitId })?.name.nilIfEmpty ?? "未命名按键组"
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

    private var completedCount: Int {
        switch step {
        case .waitingForKeys:
            return 0
        case .readyToPin:
            return 1
        case .configureGroup:
            return 2
        }
    }

    private var progress: CGFloat {
        CGFloat(completedCount) / CGFloat(max(steps.count - 1, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("三步进度")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
                Spacer()
                Button("清空状态", action: onClear)
                    .buttonStyle(.bordered)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PadTheme.subtle)
                        .frame(height: 10)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [PadTheme.accent, PadTheme.success],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * progress, height: 10)
                }
            }
            .frame(height: 10)

            HStack(spacing: 10) {
                ForEach(steps, id: \.rawValue) { item in
                    ProgressStep(
                        title: item.title,
                        subtitle: subtitle(for: item),
                        isActive: item == step,
                        isCompleted: (steps.firstIndex(of: item) ?? 0) < completedCount
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

private struct ProgressStep: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isCompleted ? PadTheme.success : (isActive ? PadTheme.accent : PadTheme.subtle))
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
            }
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(PadTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ReminderStrip: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(PadTheme.accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(PadTheme.text)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(PadTheme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PadTheme.card)
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

    var background: Color {
        switch self {
        case .info:
            return Color(red: 0.90, green: 0.95, blue: 1.0)
        case .success:
            return Color(red: 0.89, green: 0.97, blue: 0.91)
        case .warning:
            return Color(red: 1.0, green: 0.95, blue: 0.85)
        case .error:
            return Color(red: 1.0, green: 0.90, blue: 0.90)
        }
    }

    var foreground: Color {
        switch self {
        case .info:
            return Color(red: 0.13, green: 0.33, blue: 0.63)
        case .success:
            return Color(red: 0.15, green: 0.45, blue: 0.22)
        case .warning:
            return Color(red: 0.60, green: 0.38, blue: 0.06)
        case .error:
            return Color(red: 0.69, green: 0.14, blue: 0.13)
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

private struct NoticeBanner: View {
    let notice: PrimaryNotice

    var body: some View {
        let tone = NoticeTone(level: notice.level)
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tone.iconName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tone.foreground)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone.foreground)
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(tone.foreground)
                if let details = notice.details?.nilIfEmpty {
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(tone.foreground.opacity(0.92))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tone.background)
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
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(PadTheme.text)
            Text(message)
                .font(.callout)
                .foregroundStyle(PadTheme.muted)
            Text(footnote)
                .font(.caption)
                .foregroundStyle(PadTheme.muted)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(PadTheme.subtle)
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
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PadTheme.text)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(PadTheme.muted)
                    Text(actionText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(PadTheme.accent)
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

private struct FeedbackRow: View {
    let entry: RuntimeFeedbackEntry
    let isLatest: Bool

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption2.monospaced())
                .foregroundStyle(PadTheme.muted)

            Text(entry.message)
                .font(.caption.monospaced())
                .foregroundStyle(PadTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isLatest ? PadTheme.accent.opacity(0.10) : PadTheme.subtle)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
