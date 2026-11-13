import Foundation

enum AppConstants {
    static let appGroupID = "group.com.example.ndiscreen"
    static let broadcastExtensionBundleID = "com.example.ndiscreen.broadcast"
}

enum CaptureResolution: String, CaseIterable, Codable, Identifiable {
    case p720
    case p1080
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .original:
            return "原始分辨率"
        }
    }

    var detail: String {
        switch self {
        case .p720:
            return "低延迟，适合 Wi-Fi"
        case .p1080:
            return "推荐，清晰度和带宽平衡"
        case .original:
            return "最清晰，带宽和性能占用最高"
        }
    }

    func dimensions(forSourceWidth width: Int, height: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (1920, 1080) }

        switch self {
        case .p720:
            return Self.fit(width: width, height: height, maxWidth: 1280, maxHeight: 720)
        case .p1080:
            return Self.fit(width: width, height: height, maxWidth: 1920, maxHeight: 1080)
        case .original:
            return Self.even(width: width, height: height)
        }
    }

    private static func fit(width: Int, height: Int, maxWidth: Int, maxHeight: Int) -> (Int, Int) {
        let scale = min(
            min(
                Double(maxWidth) / Double(width),
                Double(maxHeight) / Double(height)
            ),
            1.0
        )
        return even(
            width: Int((Double(width) * scale).rounded()),
            height: Int((Double(height) * scale).rounded())
        )
    }

    private static func even(width: Int, height: Int) -> (Int, Int) {
        let safeWidth = max(2, width - (width % 2))
        let safeHeight = max(2, height - (height % 2))
        return (safeWidth, safeHeight)
    }
}

enum BroadcastAudioSource: String, CaseIterable, Codable, Identifiable {
    case appAudio
    case microphone
    case testTone
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appAudio:
            return "App/系统声音"
        case .microphone:
            return "麦克风"
        case .testTone:
            return "测试音"
        case .off:
            return "静音"
        }
    }
}

struct BroadcastSettings: Codable, Equatable {
    static let allowedFrameRates = [15, 24, 30, 60]
    static let storageKey = "ndiScreenBroadcastSettings"

    var sourceName: String = "iPad Screen"
    var frameRate: Int = 60
    var resolution: CaptureResolution = .p1080
    var audioSource: BroadcastAudioSource = .appAudio

    var safeSourceName: String {
        let trimmed = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? "iPad Screen" : trimmed
        return String(value.prefix(64))
    }

    var normalizedFrameRate: Int {
        Self.allowedFrameRates.contains(frameRate) ? frameRate : 30
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    static func load() -> BroadcastSettings {
        guard
            let data = defaults.data(forKey: storageKey),
            let settings = try? JSONDecoder().decode(BroadcastSettings.self, from: data)
        else {
            return BroadcastSettings()
        }

        var normalized = settings
        normalized.frameRate = settings.normalizedFrameRate
        return normalized
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        Self.defaults.set(data, forKey: Self.storageKey)
    }
}

