import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: SettingsStore

    private let backgroundTop = Color(red: 0.04, green: 0.10, blue: 0.16)
    private let backgroundBottom = Color(red: 0.03, green: 0.04, blue: 0.07)
    private let accent = Color(red: 0.18, green: 0.83, blue: 0.76)

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [backgroundTop, backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                Circle()
                    .fill(accent.opacity(0.12))
                    .frame(width: 280, height: 280)
                    .blur(radius: 50)
                    .offset(x: 150, y: -300)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        settingsCard
                        broadcastCard
                        notesCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 22)
                }
            }
            .navigationTitle("NDI Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("把 iPad 屏幕变成 NDI 源")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("使用 ReplayKit 采集屏幕，通过 NDI SDK 发送视频和音频。")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(.bottom, 4)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            cardTitle("输出设置", systemImage: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 8) {
                Text("NDI 源名称")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.58))

                TextField("iPad Screen", text: $store.settings.sourceName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }

            settingBlock("帧率") {
                Picker("帧率", selection: $store.settings.frameRate) {
                    ForEach(BroadcastSettings.allowedFrameRates, id: \.self) { rate in
                        Text("\(rate) fps").tag(rate)
                    }
                }
                .pickerStyle(.segmented)
            }

            settingBlock("分辨率") {
                Picker("分辨率", selection: $store.settings.resolution) {
                    ForEach(CaptureResolution.allCases) { resolution in
                        Text(resolution.title).tag(resolution)
                    }
                }
                .pickerStyle(.segmented)

                Text(store.settings.resolution.detail)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.46))
            }

            settingBlock("音频来源") {
                Picker("音频来源", selection: $store.settings.audioSource) {
                    ForEach(BroadcastAudioSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
            }

            if !store.appGroupAvailable {
                Label(
                    "App Group 未生效。当前签名没有保留 \(AppConstants.appGroupID)，修改帧率/分辨率/音频不会传到广播扩展。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private var broadcastCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardTitle("开始广播", systemImage: "dot.radiowaves.left.and.right")

            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(accent)
                        .frame(width: 72, height: 72)

                    BroadcastPickerView(
                        preferredExtension: AppConstants.broadcastExtensionBundleID,
                        showsMicrophoneButton: store.settings.audioSource == .microphone
                    )
                    .frame(width: 64, height: 64)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("点击右侧广播按钮")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("在系统面板中选择 “NDI Screen”，然后开始屏幕共享。")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.56))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider().overlay(.white.opacity(0.12))

            Label("修改帧率或分辨率后，需要停止并重新开始广播。", systemImage: "info.circle")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
        }
        .cardStyle()
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            cardTitle("连接提示", systemImage: "wifi")

            note("iPad 和接收端必须连接到同一个局域网。")
            note("优先使用 5 GHz Wi-Fi；1080p 60 fps 或原始分辨率建议使用有线网络。")
            note("第一次启动时，请在系统设置中允许本地网络访问。")
            note("“App 声音”会采集正在播放的 App 音频；“麦克风”需要系统广播面板中的麦克风权限。")
        }
        .cardStyle()
    }

    private func settingBlock<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
            content()
        }
    }

    private func cardTitle(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }

    private func note(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(18)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}

