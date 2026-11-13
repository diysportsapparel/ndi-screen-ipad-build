# NDI Screen for iPad

一个基于 ReplayKit + NDI SDK 的 iPad 屏幕 NDI 发送端。主 App 负责设置，
Broadcast Upload Extension 负责采集屏幕和音频，并把它们作为 NDI 源发送。

## 功能

- 将 iPad 屏幕作为 NDI High Bandwidth 视频源发送
- 支持 15 / 24 / 30 / 60 fps
- 支持 720p、1080p、原始分辨率（保持原始宽高比）
- 支持 App 音频或麦克风音频
- NDI 源名称可配置
- 输出 BGRA 视频帧，不做额外的 H.264 压缩
- 自动处理 ReplayKit 提供的视频方向

## 环境要求

- macOS 13 或更高版本
- Xcode 15 或更高版本
- XcodeGen 2.38 或更高版本
- iPadOS 16 或更高版本
- 已登录 Apple 开发者账号（签名由你自行配置）
- 官方 NDI SDK for iOS

## 1. 放置 NDI SDK

从 NDI 官方开发者站点下载 iOS SDK，并放入：

```text
Vendor/NDI/include/Processing.NDI.Lib.h
Vendor/NDI/lib/iOS/libndi_ios.a
```

NDI SDK 的头文件文件名本身带点号，例如
`include/Processing.NDI.Lib.h`，不是 `include/Processing/NDI.Lib.h`。

如果 SDK 已安装在默认位置，可以在 macOS 上执行：

```bash
mkdir -p Vendor/NDI/include Vendor/NDI/lib/iOS
cp -R "/Library/NDI SDK for Apple/include/." Vendor/NDI/include/
cp "/Library/NDI SDK for Apple/lib/iOS/libndi_ios.a" Vendor/NDI/lib/iOS/
```

如果 SDK 中的静态库目录不同，请修改 `project.yml` 里的
`LIBRARY_SEARCH_PATHS`。NDI SDK 不能随本工程重新分发，请遵守其许可证。

## 2. 修改 Bundle ID 和 App Group

需要同时修改以下位置，并保持完全一致：

- `project.yml`
  - App：`com.example.ndiscreen`
  - Extension：`com.example.ndiscreen.broadcast`
- `Shared/BroadcastSettings.swift`
  - `appGroupID`
  - `broadcastExtensionBundleID`
- `App/App.entitlements`
- `BroadcastExtension/BroadcastExtension.entitlements`

例如改成：

```text
App bundle ID:       com.yourcompany.ndiscreen
Extension bundle ID: com.yourcompany.ndiscreen.broadcast
App Group:           group.com.yourcompany.ndiscreen
```

App Group 必须在 Apple Developer 后台创建，并同时在 App 和 Extension 的
Signing & Capabilities 中启用。

## 3. 生成并编译工程

```bash
brew install xcodegen
cd NDIScreenBroadcast
xcodegen generate
open NDIScreenBroadcast.xcodeproj
```

在 Xcode 中选择：

- Team：你的开发者团队
- Bundle Identifier：与 App Group 对应的 ID
- 目标设备：你的 iPad

先连接 iPad 运行 `NDIScreen` Scheme。Xcode 会自动安装主 App 和嵌入的
Broadcast Upload Extension。

## 4. 使用

1. iPad 与 NDI 接收端连接到同一局域网。
2. 打开 `NDI Screen`，设置 NDI 源名称、帧率、分辨率、音频来源。
3. 点击页面中的广播按钮，在系统面板选择 `NDI Screen`。
4. 在接收端（NDI Studio Monitor、OBS DistroAV、vMix 等）选择同名 NDI 源。
5. 停止广播后修改设置，再次开始广播。

## 5. 生成 IPA

在 Xcode 中：

```text
Product > Archive > Distribute App
```

如果使用命令行导出，先创建 `ExportOptions.plist`，再执行：

```bash
cp ExportOptions.example.plist ExportOptions.plist
# 编辑 ExportOptions.plist，把 YOUR_TEAM_ID 改成你的 Team ID
chmod +x scripts/build-ipa.sh
./scripts/build-ipa.sh
```

`method` 可选 `development`、`ad-hoc`、`app-store` 等。最终 IPA 必须使用你的
证书和 Provisioning Profile 签名，不能直接使用未签名 IPA 安装到普通 iPad。

如果计划上架或公开分发，请同时核对 NDI SDK 的商标/署名要求。NDI 官方
SDK 通常要求在产品界面或商店页面中保留 NDI 品牌说明；个人侧载通常不受
影响，但正式发布前应以当前 NDI SDK License 为准。

## 没有 Mac 时

可以把工程推送到 GitHub，使用 macOS Actions runner 生成未签名 IPA：

```text
.github/workflows/build-unsigned-ipa.yml
```

详细步骤见 `docs/github-actions-ipa.md`。生成的是未签名
`NDIScreen-unsigned.ipa`，仍需用 Sideloadly/AltStore 或你的证书在
Windows 上签名后再安装到 iPad。

## 性能建议

- 默认使用 1080p / 30 fps / App 声音。
- 720p / 30 fps 更适合普通 Wi-Fi。
- 1080p / 60 fps 和原始分辨率建议使用 5 GHz Wi-Fi 或有线网络。
- NDI High Bandwidth 的码率较高；如果接收端卡顿，先降低分辨率或帧率。
- Broadcast Upload Extension 有内存和后台运行限制，不建议一开始就使用
  iPad 原始分辨率 + 60 fps。

## 已知限制

- 第一次使用需要允许本地网络权限；如果 NDI 源不出现，检查 iPad 的
  “设置 > 隐私与安全性 > 本地网络”。
- 主 App 与 Broadcast Extension 必须在签名时保留同一个 App Group。
  如果签名工具丢弃了 `group.com.example.ndiscreen`，Extension 会退回内置
  默认设置，表现为 App 里改了 60 fps 但接收端仍是 30 fps。
- App 音频和麦克风目前是二选一，没有做混音。
- App 音频依赖 ReplayKit 的 `audioApp` 采样以及扩展 Info.plist 中的
  `RPBroadcastProcessAudioEnabled`。DRM 视频、部分受保护音频不会进入
  ReplayKit。
- ReplayKit 屏幕广播的输入帧率由 iPadOS 决定。部分 iPad/内容只提供
  30 fps；此时即使 NDI 源声明 60 fps，接收端看到的真实帧率仍是 30 fps。
- 系统广播扩展只应在用户主动开始屏幕广播时运行。
- 本项目是源码工程，NDI 二进制和 Apple 签名材料需要你自行提供。

