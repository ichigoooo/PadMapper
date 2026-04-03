
# 自定义小键盘可视化配置工具

**产品设计文档 / PRD + 技术方案 v1**

## 1. 产品概述

### 1.1 产品名称

暂定：**PadMapper**

### 1.2 产品一句话描述

一款面向 macOS 的本地桌面工具，用于将一块独立小键盘映射为自定义快捷键、按键组合、功能单元和模式层；支持可视化布局编辑、异形键帽显示、自定义多键组合触发，以及仅作用于目标设备、不影响另一把全键盘的正常输入。

### 1.3 产品目标

解决以下问题：

* 用户有一块独立小键盘，希望把它当作“宏键盘 / 功能板”使用
* 小键盘外形并不标准，键帽可 DIY、更换、拼接，不能用传统标准键盘布局描述
* 用户需要一个**可视化界面**来定义按键，而不是手写 JSON 或代码
* 用户可能同时连接另一把全键盘，希望其输入行为保持原样，不被改动
* 用户希望支持“多个物理键一起按下，只触发一次功能单元”的组合逻辑

### 1.4 非目标

第一阶段不做这些：

* 不做云同步
* 不做跨平台 Windows/Linux
* 不做复杂脚本生态或插件市场
* 不做板载固件刷写
* 不做驱动级开发
* 不追求支持所有奇怪 HID 设备，先以“标准可识别的独立键盘 / 小键盘”作为主路径

---

## 2. 用户与场景

### 2.1 目标用户

* 有外接数字小键盘/宏键盘的 macOS 用户
* 喜欢桌面外设 DIY 的用户
* 希望把设备映射为快捷键、办公操作、创作工具快捷操作的用户
* 不想手写 Karabiner 配置的用户

### 2.2 核心使用场景

#### 场景 A：单键映射

用户把某个小键盘键映射为：

* `cmd + shift + k`
* 打开某个 App
* 触发一个系统动作
* 触发一个快捷指令

#### 场景 B：多键组合功能单元

用户在界面中选中多个物理键，定义为一个功能单元触发器：

* 例如右下角 3 个物理键同时按下 => 触发“重做功能单元”
* 功能单元内部可执行 `cmd + y`
* 按住不重复触发
* 松开后再次按下才重新触发

#### 场景 C：异形键帽可视化布局

用户设备是 3 × 6 的逻辑矩阵，但键帽可变：

* 单格键
* 横向 2u 大键
* L 形 / 拼接键帽
* “看起来像俄罗斯方块”的组合显示

用户希望在界面中编辑“键位形状”和“映射规则”，而不是仅看到标准键盘图。

#### 场景 D：双设备共存

* 小键盘 = 自定义宏板
* 全键盘 = 原始输入
* 两者同时连接，互不干扰

---

## 3. 产品定位

### 3.1 核心价值

这不是一个“普通改键器”，而是一个：

**面向独立外接小键盘的可视化配置器 + 输入运行时引擎**

### 3.2 与通用改键工具的差异

相较于 Karabiner 一类工具，本产品强调：

* 可视化布局
* 异形键帽展示
* 位置语义而不是仅靠键码
* 多键组合与功能单元的产品级配置体验
* 针对单设备的专门映射
* 面向 DIY 外设的用户体验

---

## 4. 功能需求

## 4.1 功能总览

版本优先级建议：

### P0（MVP）

* 识别目标小键盘设备
* 可视化显示 3×6 键位
* 支持自定义键形状
* 支持按键校准
* 支持单键映射
* 支持自定义多键组合映射
* 支持功能单元管理与复用
* 支持输出系统快捷键组合
* 支持仅作用于目标设备
* 支持配置保存/加载
* 支持实时启用/停用配置

### P1

* 支持多 Profile
* 支持按应用切换规则
* 支持动作链（打开 App、执行脚本、延迟动作）
* 支持冲突检测
* 支持组合录制器
* 支持快捷指令调用

### P2

* 支持模式层 / Layer
* 支持 Tap / Hold 双态
* 支持增强型可视化调试面板
* 支持配置导入导出分享
* 支持菜单栏常驻

---

## 4.2 详细功能描述

### 4.2.1 设备发现与选择

用户打开应用后，可看到当前已连接的 HID 键盘类设备列表，选择其中一块作为目标设备。

需求：

* 显示设备名
* 显示连接方式（蓝牙 / USB）
* 显示基础标识信息
* 支持“将此设备设为受管设备”
* 支持断开重连后自动恢复匹配

### 4.2.2 键位校准

由于设备外形和键帽不规则，UI 里的“第几个位置”不一定天然对应系统键码，因此必须有校准流程。

流程：

1. 用户点击界面中的一个位置
2. 应用提示“请按下目标物理键”
3. 记录该键对应的底层输入标识
4. 完成“界面位置 ↔ 实际按键输入”的绑定

要求：

* 支持逐个校准
* 支持重新校准
* 支持查看未校准位置
* 支持检测重复绑定

### 4.2.3 布局编辑器

支持构建一个 3×6 的逻辑网格，网格中的每个键位可配置：

* 坐标 row / col
* 宽高 span（如 1×1、2×1）
* 形状类型
* 显示名称
* 显示图标
* 显示颜色
* 是否可参与组合
* 是否隐藏

建议先支持三种形状：

* 标准矩形
* 横向大键
* 自定义多边形（后续）

MVP 阶段可先简化为：

* 矩形
* 横向宽键
* 预制 L 形

### 4.2.4 映射规则编辑

每条规则包含：

* 触发键集合
* 触发条件
* 目标功能单元
* 是否启用
* 优先级

支持的触发类型：

* 单键按下
* 自定义多键同时按下
* 长按（P2）
* 连击（P2）

功能单元支持的输出动作：

* 发送快捷键组合
* 发送单个虚拟键
* 打开应用
* 执行 shell 命令
* 触发快捷指令
* 切换配置层（P2）

### 4.2.5 组合键语义

必须支持：

* 任意多个物理键构成一个组合
* 同时按下时仅触发一次
* 按住期间不重复触发
* 只有在释放后再次按下才重新触发

可选参数：

* 允许的最大触发时间窗，例如 50ms
* 是否要求严格同时按下
* 是否屏蔽组成组合的单键原始功能

### 4.2.6 配置管理

支持：

* 新建配置
* 复制配置
* 重命名配置
* 删除配置
* 导出 JSON
* 导入 JSON

### 4.2.7 运行时控制

支持：

* 启用/停用整个映射系统
* 当前配置生效状态提示
* 菜单栏快速切换（P2）

---

## 5. 用户体验设计

## 5.1 信息架构

建议采用三栏布局：

### 左侧：设备与配置

* 当前设备
* Profile 列表
* 启用状态
* 校准状态

### 中间：可视化键盘画布

* 显示 3×6 键盘
* 支持点选多个键
* 支持调整键的形状、大小和标签
* 支持高亮当前按下键

### 右侧：属性与规则面板

* 当前选中键/组合的信息
* 规则配置
* 功能单元与输出动作配置
* 冲突提示
* 测试按钮

## 5.2 关键交互

### 交互 1：多键组合定义

1. 用户在画布中点击右下角多个键
2. 右侧面板显示“已选中 N 个键”
3. 用户点击“新建功能单元规则”
4. 新建或选择一个功能单元
5. 为该功能单元配置输出“快捷键”
6. 输入 `cmd + y`
7. 将当前按键组合绑定到该功能单元
8. 保存
9. 在测试模式中同时按下这些物理键，UI 高亮并显示“已触发重做功能单元”

### 交互 2：校准

1. 用户点击某个未绑定键位
2. UI 进入“等待输入”
3. 用户按下实物键
4. 绑定成功后显示底层标识
5. 若与已有位置冲突，弹出提示

### 交互 3：调试

运行时侧边栏显示：

* 当前按下集合
* 当前命中规则
* 是否已触发
* 当前输出动作

这个调试界面对开发期非常重要。

---

## 6. 数据模型设计

下面是推荐的数据结构。

## 6.1 布局模型

```ts
type KeyShapeType = "rect" | "wide" | "lshape" | "polygon";

interface LayoutKey {
  id: string;              // 逻辑键 ID，例如 K00
  row: number;
  col: number;
  width: number;           // 占用网格宽度
  height: number;          // 占用网格高度
  shapeType: KeyShapeType;
  polygonPoints?: { x: number; y: number }[];
  label?: string;
  icon?: string;
  color?: string;
  calibrateBinding?: PhysicalInputRef | null;
}
```

## 6.2 物理输入引用

```ts
interface PhysicalInputRef {
  deviceId: string;
  usagePage?: number;
  usage?: number;
  keyCode?: number;
  elementCookie?: string;
  rawValueSignature?: string;
}
```

说明：

* 这里不要把模型绑死在 `keyCode`
* 要允许未来兼容不同 HID 元素表达方式

## 6.3 动作模型

```ts
type OutputAction =
  | { type: "shortcut"; modifiers: string[]; key: string }
  | { type: "key"; key: string }
  | { type: "openApp"; bundleId: string }
  | { type: "shell"; command: string }
  | { type: "shortcutCommand"; shortcutName: string };
```

## 6.4 功能单元模型

```ts
interface FunctionUnit {
  id: string;
  name: string;
  description?: string;
  actions: OutputAction[];
  enabled: boolean;
}
```

## 6.5 规则模型

```ts
interface BindingRule {
  id: string;
  triggerKeys: string[];        // LayoutKey.id[]
  triggerType: "single" | "combo";
  triggerWindowMs?: number;     // 组合触发时间窗
  suppressIndividualKeys: boolean;
  functionUnitId: string;
  enabled: boolean;
  priority: number;
}
```

## 6.6 配置模型

```ts
interface DeviceProfile {
  id: string;
  name: string;
  deviceMatch: {
    vendorId?: number;
    productId?: number;
    transport?: string;
    serialNumber?: string;
    locationId?: string;
  };
  layout: LayoutKey[];
  functionUnits: FunctionUnit[];
  rules: BindingRule[];
  isEnabled: boolean;
}
```

---

## 7. 技术路线

## 7.1 技术选型建议

### 客户端 UI

* **SwiftUI**
* 原因：macOS 原生、界面效率高、状态驱动适合布局编辑器

### 本地持久化

* MVP：JSON 文件
* 后续：SwiftData / Core Data

### 输入设备接入

建议主路线：

* **IOHIDManager** 作为主实现，兼容范围更广
* **CoreHID** 作为后续增强方向，仅在 macOS 15+ 使用

Apple 文档说明，`IOHIDManager` 负责全局 HID 设备交互，包括设备发现、移除和接收输入事件；`IOHIDManagerSetDeviceMatching` 用于设置设备匹配条件。Apple 也提供了 `IOHIDManagerRegisterInputValueCallback` 来接收枚举设备发出的输入值。CoreHID 则是较新的 HID 框架，面向 macOS 15+，也支持和键盘等 HID 设备交互。([Apple Developer][1])

### 系统事件输出

* **CGEvent**
* 用于构造并发送系统快捷键事件

Apple 文档说明，`CGEvent` 可创建键盘事件，`init(keyboardEventSource:virtualKey:keyDown:)` 返回新的 Quartz 键盘事件，`post(tap:)` 可将事件投递回系统事件流。([Apple Developer][2])

## 7.2 为什么建议用 IOHIDManager 做 MVP

原因很简单：

* 兼容更广，不要求 macOS 15+
* 更成熟，资料更多
* 足以实现设备识别、输入接收、按设备隔离、独占设备
* 对你的目标场景已经够用

CoreHID 可以作为后续重构或增强路径，不必一开始就押上去。Apple 官方资料显示 CoreHID 是 macOS 15.0+ 的框架。([Apple Developer][3])

---

## 8. 系统架构设计

## 8.1 架构分层

建议拆成 4 层：

### A. Presentation Layer

负责：

* 设备列表
* 布局编辑器
* 规则编辑器
* 调试面板

### B. Domain Layer

负责：

* 布局模型
* 规则模型
* 功能单元模型
* Combo / Chord 解析器
* 冲突检测
* 配置读写

### C. Input Engine

负责：

* HID 设备枚举
* 设备匹配
* 输入采集
* 输入状态管理
* 原始设备输入拦截/独占

### D. Output Engine

负责：

* 生成 CGEvent
* 发送快捷键
* 执行动作
* 控制重复触发

## 8.2 推荐进程模型

### MVP

先做成**单进程 App**
优点：

* 开发简单
* 调试方便
* 适合快速验证

### 稳定版

再演进为：

* 前台 GUI App
* 后台 Helper / Agent

前台负责配置，后台负责长期监听与执行。
这样更利于开机自启、菜单栏常驻和运行时稳定性。

---

## 9. 关键技术方案

## 9.1 目标设备隔离

你的核心诉求是：

* 只接管这块小键盘
* 不影响另一把全键盘

实现策略：

1. 枚举 HID 设备
2. 根据匹配条件锁定目标设备
3. 只对该设备注册输入监听
4. 输出动作通过系统事件发送
5. 其他键盘不在受管列表内，因此保持原始输入

Apple 文档说明，`IOHIDManagerSetDeviceMatching` 可设置设备枚举匹配条件；`IOHIDManagerRegisterDeviceMatchingCallback` 和输入值回调可用于发现并接收匹配设备的输入。([Apple Developer][1])

## 9.2 如何阻止小键盘原始键值泄漏

这是成败关键。

如果不阻止，用户按下小键盘时，系统可能既收到它原始的 `1/2/3`，又收到你合成的快捷键，体验会出问题。

推荐路线：

* 打开目标设备时尝试使用**独占**模式
* 让系统和其他客户端不再直接接收该设备的原始事件
* 应用自己解释输入，再输出新动作

Apple 文档说明，`IOHIDManagerOpen` 可使用 `kIOHIDOptionsTypeSeizeDevice` 建立独占链接；该选项会阻止系统和其他客户端接收该设备事件。([Apple Developer][4])

这是 MVP 最值得先做的技术验证点。

## 9.3 组合键引擎 Chord Engine

这是产品核心逻辑之一。

### 状态结构

```ts
activePhysicalKeys: Set<PhysicalInputRef>
activeLogicalKeys: Set<LayoutKeyId>
firedRules: Set<RuleId>
```

### 触发流程

1. 收到按下事件
2. 将物理键映射为逻辑键
3. 更新 `activeLogicalKeys`
4. 遍历规则，检查是否命中
5. 若命中且未触发，则执行动作并记录到 `firedRules`
6. 收到释放事件时更新集合
7. 当某规则已不再满足时，从 `firedRules` 中移除

### 触发条件

对于 `{K24, K25, K26} -> redoUnit`：

* 当 `activeLogicalKeys` 包含 `K24`、`K25` 和 `K26`
* 且该规则尚未触发
* 则执行一次 `redoUnit`
* 直到其中任一键释放前，不再重复执行

### 可选增强

* 加入 `triggerWindowMs`
* 例如要求整组按键在 80ms 内进入按下态才算组合

## 9.4 单键与组合键冲突处理

这是很常见的产品设计问题。

例如：

* K24 单键 = `undo`
* K25 单键 = `redo`
* K24 + K25 + K26 = `redoUnit`

若直接立即触发单键，就会与多键组合或其子集组合冲突。

解决策略建议分层：

### MVP

先限制：

* 用于复杂组合的键，默认不再定义冲突单键动作
* 组合规则优先级高于其真子集规则

### P1

加入“组合判定等待窗”：

* 键按下后先延迟 30~80ms
* 期间若形成组合，则触发组合
* 否则触发单键

这样更像成熟产品，但实现复杂度更高。

---

## 10. 输出动作设计

## 10.1 快捷键输出

例如 `cmd + y`：

伪代码：

```swift
send(.command, down: true)
send(.y, down: true)
send(.y, down: false)
send(.command, down: false)
```

用 `CGEvent` 生成并投递。Apple 文档说明 CGEvent 可构造键盘事件并投递到系统事件流。([Apple Developer][2])

## 10.2 Shell / App / 快捷指令

后续可以增加：

* 打开指定 App
* 调用 shell command
* 执行快捷指令

这一层建议统一抽象为 `OutputActionExecutor`。

---

## 11. 权限与系统约束

这是必须在产品文档里明确写出的部分。

### 11.1 HID 访问

Apple 文档明确指出，与某些 HID（例如键盘）交互需要用户批准。([Apple Developer][5])

所以产品必须有：

* 首次启动引导
* 权限状态检测
* 失败时的明确提示文案

### 11.2 事件监听 / 低层输入处理

Apple 文档说明，Quartz Event Services 提供 event taps，可在系统中监控和过滤低层输入事件；`CGEvent.tapCreate` 用于建立事件 tap。文档也说明，接收键盘 key up / key down 事件需要相应的辅助功能访问条件。([Apple Developer][6])

MVP 主路线可以优先依赖 HID 设备输入，不把 event tap 作为第一依赖；但若后续要做更复杂的全局键盘上下文判断、应用级过滤或冲突监控，event tap 仍然是重要能力。([Apple Developer][6])

### 11.3 平台兼容

* IOHIDManager：适合做广覆盖方案
* CoreHID：适合未来 macOS 15+ 优化路径

因此建议：

* **最低支持版本**：macOS 13/14 起步
* **主实现**：IOHIDManager
* **可选增强**：macOS 15+ 使用 CoreHID

这是一个更稳妥的版本策略。CoreHID 官方文档当前标注为 macOS 15.0+。([Apple Developer][3])

---

## 12. MVP 范围定义

### 12.1 MVP 必须交付

* 选择目标设备
* 3×6 画布显示
* 基本键位形状
* 校准流程
* 单键规则
* 多键组合规则
* 功能单元配置
* 快捷键输出
* 配置本地保存
* 启用/停用
* 调试面板

### 12.2 MVP 不做

* 多设备同时映射
* 多层模式
* 高级脚本
* 按 App 切换配置
* 菜单栏常驻
* 自动同步

---

## 13. 开发计划建议

## 第一阶段：技术验证 Spike（1 周）

目标：确认最关键的可行性

需要验证 4 件事：

1. 能否稳定识别目标设备
2. 能否拿到目标设备的每个物理按键输入
3. 能否用独占方式阻止原始输入泄漏
4. 能否让 N 键组合稳定触发一个功能单元，并合成发送 `cmd+y` 这类系统快捷键

只要这 4 件事成立，产品就能做。

## 第二阶段：MVP 内核（1~2 周）

* DeviceManager
* HID 输入监听
* Combo / Chord Engine
* Function Unit Registry
* Action Executor
* JSON 配置

## 第三阶段：可视化配置器（1~2 周）

* 3×6 画布
* 校准 UI
* 规则编辑 UI
* 测试与调试 UI

## 第四阶段：稳定性与打磨（1 周）

* 异常恢复
* 断连重连
* 冲突提示
* 权限提示
* 配置导入导出

---

## 14. 风险与应对

### 风险 1：部分物理键无法独立识别

有些奇怪小键盘在系统里未必把每个位置都暴露为可区分的输入元素。

应对：

* 先做校准探测页
* 将“可独立识别”作为设备兼容性前提
* 对无法区分的键给出提示

### 风险 2：独占设备失败

某些设备或系统场景下，独占模式可能不稳定。

应对：

* 把“独占模式”做成技术验证的最高优先级
* 失败时降级为“监听 + 尽力过滤”的兼容模式
* 在 UI 中告知“该设备当前未完全隔离原始输入”

### 风险 3：多键组合与单键/子集组合冲突

应对：

* MVP 阶段避免复杂冲突
* 先建立“最长匹配优先 + 高优先级优先”规则
* 后续加入时间窗判定

### 风险 4：权限问题

应对：

* 启动时统一检测
* 把失败原因写清楚
* 提供“打开系统设置”的入口

---

## 15. 推荐代码结构

```text
PadMapper/
  App/
    PadMapperApp.swift
    MainWindow.swift

  UI/
    DeviceListView.swift
    LayoutCanvasView.swift
    RuleEditorView.swift
    CalibrationView.swift
    DebugPanelView.swift

  Domain/
    Models/
      DeviceProfile.swift
      LayoutKey.swift
      BindingRule.swift
      FunctionUnit.swift
      OutputAction.swift
    Services/
      ChordResolver.swift
      ConflictDetector.swift
      ProfileStore.swift

  Infra/
    HID/
      HIDDeviceManager.swift
      HIDInputParser.swift
      HIDCalibrationService.swift
    Output/
      ShortcutEmitter.swift
      ActionExecutor.swift

  Support/
    Permissions/
    Logging/
    Utils/
```

---

## 16. 最终建议

对于你这个项目，我建议你不要一开始追求“大而全”，而是先把下面这条链路打通：

**识别设备 → 校准 18 个位置 → 选中多个键 → 绑定到一个功能单元 → 功能单元执行 `cmd+y` → 同时按下只触发一次 → 全键盘不受影响**

只要这条链通了，这个产品就已经成立了。

真正的工程优先级只有三个：

1. **设备隔离**
2. **稳定的多键组合状态机与功能单元抽象**
3. **好用的可视化配置体验**
