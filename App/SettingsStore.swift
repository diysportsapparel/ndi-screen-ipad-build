import SwiftUI

final class SettingsStore: ObservableObject {
    @Published private(set) var appGroupAvailable: Bool

    @Published var settings: BroadcastSettings {
        didSet {
            settings.save()
        }
    }

    init() {
        let groupDefaults = UserDefaults(suiteName: AppConstants.appGroupID)
        groupDefaults?.set("ok", forKey: "ndiScreenAppGroupCheck")
        appGroupAvailable =
            groupDefaults?.string(forKey: "ndiScreenAppGroupCheck") == "ok"
        settings = BroadcastSettings.load()
    }
}

