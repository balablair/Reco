<p align="center">
  <img width="150" height="150" src="Sources/Reco/Resources/AppIcon.svg" alt="Reco">
</p>

<h1 align="center">Reco</h1>

<p align="center">
  专为内容创作者打造的 macOS 录制工作台
  <br />
  屏幕录制 · 摄像头 PiP · 智能自动缩放 · 提词器 · 一键导出
  <br /><br />
  <b>系统要求：</b>macOS 14+
</p>

---

Reco 是一款面向短视频创作者（抖音 / 小红书 / B站）的 macOS 录制工具。在一个悬浮工作台中完成录制准备、实时录制、后期剪辑与导出，无需在多个 App 之间反复切换。

## 功能亮点

### 智能自动缩放（Smart Auto-Zoom）

录制过程中实时追踪鼠标点击位置。导出时自动在每次点击处生成一段缩放动画：镜头以 easeOut 曲线快速拉近到点击区域，保持一段时间后以 easeIn 曲线平滑退回全屏。连续点击会自动合并为一段，避免频繁抖动。所有参数（缩放倍率、预拉时间、保持时长、退出时长、合并阈值）均可在设置中调节。整个过程无需手动打关键帧，导出即得。

### 多平台画布模式

内置抖音（9:16）、小红书（3:4）、B站（16:9）等主流平台模板，切换平台时画布自动按目标比例重排，无需手动调整尺寸。

### 摄像头画中画（PiP）

实时采集摄像头画面叠加在屏幕录制内容之上，支持圆形 / 圆角矩形 / 直角矩形等多种裁剪形状、拖拽调整位置与尺寸，以及磨皮、亮度、饱和度等美颜参数调节。

### 提词器

内置悬浮提词器面板，支持自动滚动、实时调速（+/-）、随时切换编辑模式，不遮挡录制区域。

### 多轨音频

同时录制麦克风人声与系统内录音频，合成至同一输出文件，省去后期对轨步骤。

### 内置剪辑器

录制完成后直接进入编辑器，支持时间轴缩略图预览、首尾裁剪（Trim）与实时播放。

### 一键导出

导出为 MP4（H.264），可自定义分辨率与码率，完成后直接在 Finder 中定位文件。

### 偏好持久化

所有设置（平台选择、画布布局、提词器内容、美颜参数、覆层开关）在重启后自动恢复，版本升级时逐字段容错，不会整体丢失。

### 权限引导

首次使用时，若录屏或摄像头权限未授权，PrepBar 会主动提示并一键跳转系统设置，降低上手门槛。

---

## 使用方式

### 直接打包运行（推荐）

```bash
git clone git@github.com:balablair/Reco.git
cd Reco
bash make-app.sh release
open Reco.app
```

### 从源码构建

```bash
swift build -c release
.build/arm64-apple-macosx/release/Reco
```

> 首次启动会弹出录屏、摄像头、麦克风权限请求，全部允许后即可正常使用。  
> 如提示"来自身份不明的开发者"，在**系统设置 → 隐私与安全性**中点击「仍要打开」即可。

---

## 技术架构

| 模块 | 说明 |
|------|------|
| `RecoKit` | 核心能力库：ScreenCaptureKit 采集、AVFoundation 合成、Auto-Zoom 算法、AppViewModel |
| `Reco` | macOS 应用层：SwiftUI 界面、悬浮面板、NSPanel 窗口管理 |
| `RecoTests` | 单元测试 |

**主要技术栈：**
- Swift 6 + SwiftUI
- ScreenCaptureKit（屏幕录制与鼠标事件追踪）
- AVFoundation（摄像头 PiP 合成、音频混流、逐帧 Auto-Zoom 渲染、视频导出）
- AppKit NSPanel（悬浮窗口系统）
- UserDefaults + JSON（偏好持久化，逐字段容错解码）

---

## 系统要求

- macOS 14.0（Sonoma）或更高版本
- Apple Silicon（arm64）
- 权限：录屏、摄像头、麦克风

---

## License

MIT
