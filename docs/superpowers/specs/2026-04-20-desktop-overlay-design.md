# Desktop Overlay UI — Design Spec
_2026-04-20_

---

## 目标

将 CreatorRecorder 的主工作流从 Studio 窗口迁移到真实桌面浮层。整个录制流程（准备 → 录制 → 完成）全部在桌面上以 NSPanel 浮层完成，Studio 仅在用户主动点击"Open in Studio"时打开。

---

## 架构方案：A+

| 阶段 | 承载容器 | 行为 |
|---|---|---|
| 启动 | Prep Bar（NSPanel） | 应用启动后直接显示桌面浮层，不打开 Studio |
| 准备 | Prep Bar | 用户配置选区、摄像头、提词器、麦克风 |
| 录制中 | Rec HUD（NSPanel） | Prep Bar 隐藏，HUD 浮在录制区顶部 |
| 完成 | Completion Card（NSPanel） | HUD 消失，Completion Card 出现在右下角 |
| 编辑 | Studio 窗口 | 仅在用户点击"Open in Studio"后打开 |

---

## 组件规格

### 1. Prep Bar

**形态**：水平胶囊，浮于屏幕底部居中，`100px` border-radius。

**内容（从左到右）**：
```
● [绿点]  1280 × 720  |  [📷] [≡] [🎙] [⊡]  |  ⏺ Record
```

| 元素 | 说明 |
|---|---|
| 绿点 `pip-green` | 状态指示，就绪时显示 |
| `1280 × 720` | 当前录制区域尺寸，无标题行 |
| 分隔线 `sep` | `margin: 0 6px` 渐变线 |
| Camera chip | `34×34px` 圆形 chip，可开关，`fill` icon |
| Teleprompter chip | 同上，4行文字对齐 icon |
| Mic chip | 同上，麦克风 icon |
| Pick Area chip | 同上，四角虚线框 icon，`off` 状态（灰色），点击进入选区模式 |
| 分隔线 |  |
| Record CTA | 黑底胶囊按钮，红色 `⏺` 圆点 + "Record" |

**尺寸**：`padding: 11px 12px 11px 20px`，`gap: 10px`

---

### 2. Rec HUD

**形态**：深色胶囊（`glass-hud`），浮于录制区顶部居中，录制区域用红色 `1.5px` 描边。

**内容**：
```
● REC  02:47  |  ⏹ Stop
```

| 元素 | 说明 |
|---|---|
| 红点 + REC | 闪烁动画，`#ff453a`，`font-weight: 700` |
| 计时器 | `tabular-nums`，`13px` |
| 分隔线 `sep-hud` | 白色渐变线 |
| Stop 按钮 | 白底胶囊，`⏹` 图标 + "Stop" |

**尺寸**：`padding: 10px 18px`，`gap: 10px`

---

### 3. Completion Card

**形态**：`glass` 卡片，浮于屏幕右下角，`16px` border-radius，`310px` 宽。

**内容（从上到下）**：
1. 缩略图（`80px` 高，`10px` radius，居中播放按钮）
2. 元数据行：`02:47 · 284 MB`（无文件名）
3. 次要操作行：`↩ Redo`、`✂ Trim`、`↗ Share`（等宽胶囊按钮）
4. 主操作：`Open in Studio →`（全宽黑底胶囊）

**间距**：`padding: 16px`，两行按钮 `gap: 10px`

---

## 视觉规范

### 材质：Liquid Glass

```
Light (glass):
  background: rgba(255,255,255,0.72)
  backdrop-filter: blur(40px) saturate(2.0) brightness(1.04)
  border-top: rgba(255,255,255,0.90) — specular edge
  border-bottom: rgba(0,0,0,0.08)
  box-shadow: inset 0 1px 0 rgba(255,255,255,0.95)  ← 内高光

Dark (glass-hud):
  background: rgba(28,28,30,0.78)
  backdrop-filter: blur(40px) saturate(1.8) brightness(0.9)
  border-top: rgba(255,255,255,0.22)
```

### 圆角规范（SnowUI 对齐）

| 层级 | 值 |
|---|---|
| 胶囊容器（prep bar、rec hud） | `100px` |
| 胶囊内元素（chip、CTA、stop） | `100px`（nested corner radius） |
| 卡片容器（completion card） | `16px` |
| 卡片内缩略图 | `10px` |

### 颜色

| 用途 | 值 |
|---|---|
| 文字主色 | `rgba(0,0,0,0.85)` |
| 文字次色 | `rgba(0,0,0,0.55)` |
| 文字弱色 | `rgba(0,0,0,0.38)` |
| chip on | `rgba(0,0,0,0.08)` 背景 |
| chip off | 透明 |
| CTA 背景 | `rgba(0,0,0,0.82)` |
| 录制红色 | `#ff3b30`（pip）/ `#ff453a`（REC label） |
| 就绪绿色 | `#28cd41` |

### 字体

`-apple-system, BlinkMacSystemFont, 'SF Pro Text'`，`-webkit-font-smoothing: antialiased`

---

## NSPanel 结构

```
App 启动
  └─ PrepBarPanel (NSPanel, level: floating)
       ├─ 始终显示在桌面上方
       ├─ 点击 Record → 隐藏自身，显示 RecHUDPanel + 录制区描边
       └─ 录制结束 → 隐藏 RecHUDPanel，显示 CompletionPanel

RecHUDPanel (NSPanel, level: floating)
  └─ 点击 Stop → 停止录制，隐藏自身，显示 CompletionPanel

CompletionPanel (NSPanel, level: floating)
  ├─ 点击 Redo → 隐藏自身，显示 PrepBarPanel
  └─ 点击 Open in Studio → 打开 Studio 窗口
```

---

## AppViewModel 状态重构

```swift
enum AppPhase {
    case preparation   // PrepBarPanel 可见
    case recording     // RecHUDPanel 可见 + 红框
    case completion    // CompletionPanel 可见
    case editing       // Studio 窗口可见
}
```

当前的 `currentScreen: Screen` 枚举替换为 `phase: AppPhase`，各 Panel 监听对应 phase 显示/隐藏。

---

## 文件影响范围

| 文件 | 变更类型 |
|---|---|
| `AppViewModel.swift` | 重构状态模型 → `AppPhase` |
| `CreatorRecorder.swift` | 新增 `PrepBarPanel`、`RecHUDPanel`、`CompletionPanel` 三个 NSPanel；`StudioWindowController` 改为按需打开 |
| `AppShellView.swift` | 仅保留 EditorScreenView，其余 screen 移除 |
| `PrepBarView.swift` | 新文件，实现 Prep Bar 浮层内容 |
| `RecHUDView.swift` | 新文件，实现 Rec HUD 浮层内容 |
| `CompletionCardView.swift` | 新文件，实现 Completion Card 浮层内容 |
| `PreparationScreenView.swift` | 保留逻辑，UI 迁移到 PrepBarView |
| `RecordingScreenView.swift` | 保留逻辑，UI 迁移到 RecHUDView |
| `Domain.swift` | 新增 `AppPhase` 枚举 |
| `SharedViews.swift` | GlassTag 等组件按需复用到 Panel |
| `TopBarView.swift` | ModeSwitcherView 移除或仅保留 Studio 内 |
| `TrimBarView.swift` | Studio-only，保留不动 |

---

## 补充：边界场景与状态细节

### 状态流转完整图

```
preparation
  ├─(Pick Area)────→ 选区模式(regionSelectionActive=true, PrepBar隐藏)
  │                    └─(完成选区) ─→ preparation(PrepBar重新显示,尺寸更新)
  ├─(Record)───────→ recording
  │                    ├─(失败) ──────→ preparation + 错误 Toast
  │                    └─(Stop) ──────→ completion
  └─ completion
       ├─(Redo) ────→ preparation
       ├─(Trim) ────→ editing(打开 Studio，进入 trim 模式)
       ├─(Share) ───→ 调用系统 NSSharingService（不切换 phase）
       └─(Open in Studio) → editing(打开 Studio)
```

### 录制失败处理
- `stopRecordingSession()` 成功 → phase = `.completion`
- 录制中断/失败 → phase = `.preparation`，显示系统 Alert 或 Toast

### 录制计时器
- `AppViewModel` 新增 `recordingElapsedSeconds: Int`
- 录制开始时启动 `Timer.scheduledTimer`，每秒 +1
- 录制结束时停止并重置

### 区域选区协调
- 点击 Pick Area chip → `regionSelectionActive = true`，PrepBarPanel `orderOut`
- `DesktopRegionPicker` 完成/取消 → `regionSelectionActive = false`，PrepBarPanel `makeKeyAndOrderFront`

---

## NSPanel 层级与结构

```
level 分配：
  PrepBarPanel    → .floating
  RecHUDPanel     → .floating
  CompletionPanel → .floating
  录制红框 Panel   → .floating + ignoresMouseEvents = true（透明背景仅绘制描边）
  DesktopRegionPicker → .screenSaver（保持现有逻辑）
```

### 推荐文件结构

```
Sources/CreatorRecorder/
├── Panels/
│   ├── FloatingPanelWindow.swift     ← 共享 NSPanel 基类
│   ├── PrepBarPanel.swift            ← NSPanel 管理 + PrepBarView
│   ├── RecHUDPanel.swift             ← NSPanel 管理 + RecHUDView
│   ├── CompletionPanel.swift         ← NSPanel 管理 + CompletionCardView
│   └── RecordingOutlinePanel.swift   ← 录制区红框透明窗口
├── UI/
│   ├── PrepBarView.swift
│   ├── RecHUDView.swift
│   ├── CompletionCardView.swift
│   └── AppShellView.swift            ← 仅保留 EditorScreenView
├── Pickers/
│   └── DesktopRegionPicker.swift     ← 从 CreatorRecorder.swift 拆出
├── AppRuntime.swift
└── AppDelegate.swift
```

---

## AppViewModel 属性归属

| 属性 | 归属 |
|---|---|
| `phase: AppPhase` | 全局，替换 `currentScreen` |
| `regionSelectionActive` | 全局，保留 |
| `recordingElapsedSeconds` | 全局，新增 |
| `project: RecordingProject` | 全局，保留 |
| `selectedPlatform` | 全局，保留 |
| `exportSelection` / `exportState` | Completion + Studio 共用 |
| `playbackState` / `playbackPositionSeconds` | Studio-only |
| `inspectorPresented` | Studio-only |
