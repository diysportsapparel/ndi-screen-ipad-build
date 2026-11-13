# 没有 Mac 时构建 iPad IPA

这个方案使用 GitHub Actions 的 macOS runner 编译工程，产出一个
`NDIScreen-unsigned.ipa`。该 IPA 还没有签名，需要在 Windows 上用
Sideloadly、AltStore 或其他签名工具使用你的 Apple 账号/证书安装。

## 1. 创建 GitHub 仓库

把 `NDIScreenBroadcast` 目录推送到一个 GitHub 仓库。建议使用私有仓库，
因为 NDI SDK 不是开源软件。

工作流使用手动触发，不会在你每次推送时自动运行。

## 2. 准备 NDI SDK

推荐把官方 NDI iOS SDK 压缩包作为同一仓库的 Release 资源：

1. 在 GitHub 仓库中创建 Release。
2. Tag 填 `ndi-sdk`。
3. 上传一个包含 NDI SDK 的 `.zip` 文件。

工作流会用：

```bash
gh release download ndi-sdk --pattern '*.zip'
```

自动下载并整理头文件和 `libndi_ios.a`。

如果你不想使用 Release，也可以在仓库 Settings > Secrets and variables >
Actions 中增加 `NDI_SDK_URL`，值填一个可被 Actions 访问的 SDK zip 下载地址。

也可以手动把文件放到：

```text
Vendor/NDI/include/Processing.NDI.Lib.h
Vendor/NDI/lib/iOS/libndi_ios.a
```

这样工作流会跳过下载。

## 3. 修改 Bundle ID 和 App Group

在推送到 GitHub 前，至少修改：

- `project.yml`
- `Shared/BroadcastSettings.swift`
- `App/App.entitlements`
- `BroadcastExtension/BroadcastExtension.entitlements`

App、Extension 和 App Group 必须是你在 Apple Developer 账号下创建的
同一组标识。

## 4. 运行工作流

打开 GitHub 仓库：

```text
Actions > Build unsigned iPad IPA > Run workflow
```

等待 macOS runner 完成：

```text
archive unsigned app
package unsigned IPA
upload artifact
```

在本次运行页面底部下载 `NDIScreen-unsigned-ipa` 工件，里面就是
`NDIScreen-unsigned.ipa`。

## 5. 在 iPad 上安装

未签名 IPA 不能直接安装。你需要用 Windows 上的签名工具处理：

1. 用 Sideloadly / AltStore 导入 IPA。
2. 使用你的 Apple ID 或开发者证书签名。
3. iPad 信任证书后安装。

注意：主 App 和 Broadcast Upload Extension 都包含在 IPA 中。签名时必须让
主 App 和 `NDIScreenBroadcast.appex` 都能使用同一个 App Group，否则设置无法
在两者之间共享。免费 Apple ID 可能会限制 App Group 或有效期（通常 7 天），
长期使用建议使用付费开发者账号。

## 6. 签名后检查

安装后打开 App，确认：

- 能看到输出设置页面
- 点击广播按钮能看到 `NDI Screen`
- 开始广播后接收端能发现同名 NDI 源
- 画面和声音都正常

如果 NDI 源不出现，先检查 iPad 的“设置 > 隐私与安全性 > 本地网络”。

