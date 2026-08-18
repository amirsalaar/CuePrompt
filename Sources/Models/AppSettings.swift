import Foundation

/// App-wide settings with safe migration (adding new keys won't wipe prefs).
struct AppSettings: Codable, Equatable {
    // Appearance
    var fontSize: Double = 38
    var fontName: String = "New York"
    var textOpacity: Double = 0.4  // opacity for already-read text
    var lineSpacing: Double = 1.4

    // Behavior
    var countdownDuration: Int = 3
    var autoExpandOnStart: Bool = true
    var collapseOnFinish: Bool = true
    var finishFadeDelay: TimeInterval = 3.0

    // Speech
    var preferredProvider: String = "Apple Speech"
    var preferredModel: String = "openai_whisper-base"

    // Window
    var expandedWidth: Double = 800
    var expandedHeight: Double = 400
    var showThumbnails: Bool = true
    var thumbnailPosition: ThumbnailPosition = .right
    var targetDisplayID: UInt32?  // nil = auto (camera screen)

    enum ThumbnailPosition: String, Codable, CaseIterable {
        case left, right
    }

    // MARK: - Custom Decoder for Safe Migration

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Decode each field with a default fallback — new keys won't crash
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 38
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "New York"
        textOpacity = try container.decodeIfPresent(Double.self, forKey: .textOpacity) ?? 0.4
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 1.4
        countdownDuration = try container.decodeIfPresent(Int.self, forKey: .countdownDuration) ?? 3
        autoExpandOnStart =
            try container.decodeIfPresent(Bool.self, forKey: .autoExpandOnStart) ?? true
        collapseOnFinish =
            try container.decodeIfPresent(Bool.self, forKey: .collapseOnFinish) ?? true
        finishFadeDelay =
            try container.decodeIfPresent(TimeInterval.self, forKey: .finishFadeDelay) ?? 3.0
        preferredProvider =
            try container.decodeIfPresent(String.self, forKey: .preferredProvider) ?? "WhisperKit"
        preferredModel =
            try container.decodeIfPresent(String.self, forKey: .preferredModel)
            ?? "openai_whisper-tiny"
        expandedWidth = try container.decodeIfPresent(Double.self, forKey: .expandedWidth) ?? 800
        expandedHeight = try container.decodeIfPresent(Double.self, forKey: .expandedHeight) ?? 400
        showThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showThumbnails) ?? true
        thumbnailPosition =
            try container.decodeIfPresent(ThumbnailPosition.self, forKey: .thumbnailPosition)
            ?? .right
        targetDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .targetDisplayID)
    }

    // MARK: - Persistence

    private static let key = "com.cueprompt.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else { return AppSettings() }
        return (try? JSONDecoder().decode(AppSettings.self, from: data)) ?? AppSettings()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
