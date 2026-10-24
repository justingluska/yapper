import Foundation

/// User settings shared by the app and the keyboard (App Group defaults).
enum Settings {
    enum Key {
        static let sessionMinutes = "settings.sessionMinutes"
        static let removeFillers = "settings.removeFillers"
        static let removeRepeats = "settings.removeRepeats"
        static let replacements = "settings.replacements"
        static let historyDays = "settings.historyDays"
        static let haptics = "settings.haptics"
        static let onboarded = "settings.onboarded"
        static let modelChoice = "settings.modelChoice"
        static let parakeetOnly = "settings.parakeetOnly"
        static let copyEveryDictation = "settings.copyEveryDictation"
        static let recordingDays = "settings.recordingDays"
        static let recordingHours = "settings.recordingHours"
        static let wantsModelDownload = "settings.wantsModelDownload"
        static let loadedModels = "settings.loadedModels"
        static let appleWhileLoading = "settings.appleWhileLoading"
        static let loadTimings = "settings.loadTimings"
        static let returnToApp = "settings.returnToApp"
    }

    private static var defaults: UserDefaults { Bridge.defaults }

    /// How long the microphone stays ready after the last dictation. 0 means
    /// until the user ends it.
    /// No "until I turn it off": the mic must never stay on longer than the
    /// Live Activity that shows it (and App Review expects a limit).
    static let sessionChoices = [5, 15, 60]

    static var sessionMinutes: Int {
        get {
            let stored = defaults.object(forKey: Key.sessionMinutes) as? Int ?? 15
            return sessionChoices.contains(stored) ? stored : 60
        }
        set { defaults.set(newValue, forKey: Key.sessionMinutes) }
    }

    /// "15 minutes", "an hour": how long the mic stays ready, for sentences.
    static var sessionLabel: String {
        let minutes = sessionMinutes
        return minutes == 0 ? "until you turn it off" : minutes >= 60 ? "an hour" : "\(minutes) minutes"
    }

    static var removeFillers: Bool {
        get { defaults.object(forKey: Key.removeFillers) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.removeFillers) }
    }

    static var removeRepeats: Bool {
        get { defaults.object(forKey: Key.removeRepeats) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.removeRepeats) }
    }

    /// After the keyboard opens Yapper to start listening, go straight back
    /// to the app the user was typing in.
    static var returnToApp: Bool {
        get { defaults.object(forKey: Key.returnToApp) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.returnToApp) }
    }

    static var haptics: Bool {
        get { defaults.object(forKey: Key.haptics) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.haptics) }
    }

    /// Days to keep history; 0 keeps nothing, -1 keeps everything (the default).
    static var historyDays: Int {
        get { defaults.object(forKey: Key.historyDays) as? Int ?? -1 }
        set { defaults.set(newValue, forKey: Key.historyDays) }
    }

    /// Never fall back to Apple's recognizer: a dictation waits for Parakeet,
    /// or fails with a clear error when Parakeet isn't downloaded.
    static var parakeetOnly: Bool {
        get { defaults.bool(forKey: Key.parakeetOnly) }
        set { defaults.set(newValue, forKey: Key.parakeetOnly) }
    }

    /// Put every finished dictation on the clipboard, including the ones the
    /// keyboard types for you, so it can be pasted again anywhere.
    static var copyEveryDictation: Bool {
        get { defaults.object(forKey: Key.copyEveryDictation) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.copyEveryDictation) }
    }

    /// Hours to keep the audio of each dictation, for playing back and
    /// transcribing again; 0 keeps none, -1 keeps everything. Separate from
    /// the text history, which outlives it.
    static var recordingHours: Int {
        get {
            if let hours = defaults.object(forKey: Key.recordingHours) as? Int { return hours }
            // Up to 1.0 the setting was in days (1, 7 or 30, 0 or -1).
            if let days = defaults.object(forKey: Key.recordingDays) as? Int { return days > 0 ? days * 24 : days }
            return Retention.defaultRecordingHours
        }
        set { defaults.set(newValue, forKey: Key.recordingHours) }
    }

    /// The user asked for the model download and it hasn't finished. Yapper
    /// resumes it whenever it comes back to the foreground, since iOS stops
    /// downloads when the app is suspended (for example during onboarding's
    /// trips to iOS Settings).
    static var wantsModelDownload: Bool {
        get { defaults.bool(forKey: Key.wantsModelDownload) }
        set { defaults.set(newValue, forKey: Key.wantsModelDownload) }
    }

    /// Models that have been loaded on this iPhone at least once. The first
    /// load compiles the model for this device and takes minutes; later
    /// loads take seconds.
    static var loadedModels: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.loadedModels) ?? []) }
        set { defaults.set(Array(newValue), forKey: Key.loadedModels) }
    }

    /// Don't wait for Parakeet: while it's still loading, dictations go to
    /// Apple's on-device model straight away.
    static var appleWhileLoading: Bool {
        get { defaults.bool(forKey: Key.appleWhileLoading) }
        set { defaults.set(newValue, forKey: Key.appleWhileLoading) }
    }

    /// How long each model's last ordinary (not first-ever) load took, step
    /// by step, keyed by `ModelChoice` raw value.
    static func loadTimings(for model: String) -> LoadTimings? {
        guard let data = defaults.data(forKey: Key.loadTimings),
              let all = try? JSONDecoder().decode([String: LoadTimings].self, from: data) else { return nil }
        return all[model]
    }

    static func setLoadTimings(_ timings: LoadTimings, for model: String) {
        var all = (defaults.data(forKey: Key.loadTimings))
            .flatMap { try? JSONDecoder().decode([String: LoadTimings].self, from: $0) } ?? [:]
        all[model] = timings
        defaults.set(try? JSONEncoder().encode(all), forKey: Key.loadTimings)
    }

    static var onboarded: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        set { defaults.set(newValue, forKey: Key.onboarded) }
    }

    static var replacements: [Replacement] {
        get {
            guard let data = defaults.data(forKey: Key.replacements) else { return [] }
            return (try? JSONDecoder().decode([Replacement].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.replacements) }
    }

    static var processorOptions: TextProcessor.Options {
        TextProcessor.Options(removeFillers: removeFillers, removeRepeats: removeRepeats, replacements: replacements)
    }
}

/// Dictation history as one JSON file in the App Group container, so the
/// keyboard can offer recent items for re-insertion.
enum HistoryStore {
    static var fileURL: URL? {
        Bridge.containerURL?.appendingPathComponent("history.json")
    }

    static func load() -> [DictationRecord] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([DictationRecord].self, from: data)) ?? []
    }

    static func save(_ records: [DictationRecord]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Newest first, pruned to the retention setting.
    static func append(_ record: DictationRecord) {
        var records = load()
        records.insert(record, at: 0)
        save(prune(records))
    }

    /// Replaces a record in place (after transcribing it again, or when its
    /// recording is removed).
    static func update(_ record: DictationRecord) {
        var records = load()
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        save(records)
    }

    static func prune(_ records: [DictationRecord], days: Int = Settings.historyDays, now: Date = Date()) -> [DictationRecord] {
        if days < 0 { return records }
        if days == 0 { return Array(records.prefix(1)) } // keep the last one so a failed insert is recoverable
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return records.filter { $0.date >= cutoff }
    }
}

/// Totals per day, kept apart from History so deleting dictations (or a short
/// history setting) doesn't erase your stats.
enum StatsStore {
    typealias Day = DayTotals

    private static let key = "stats.days"

    /// Keyed by "yyyy-MM-dd" in the local calendar.
    static func load() -> [String: Day] {
        guard let data = Bridge.defaults.data(forKey: key),
              let days = try? JSONDecoder().decode([String: Day].self, from: data) else {
            return backfill()
        }
        return days
    }

    static func record(words: Int, seconds: Double, on date: Date = Date()) {
        var days = load()
        var day = days[dayKey(date)] ?? Day()
        day.words += words
        day.dictations += 1
        day.seconds += seconds
        days[dayKey(date)] = day
        save(days)
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Folds in totals from an import. Per day, each total takes the larger
    /// of the two, so importing the same export twice changes nothing.
    static func merge(_ incoming: [String: Day]) {
        save(DayTotals.merged(load(), incoming))
    }

    private static func save(_ days: [String: Day]) {
        Bridge.defaults.set(try? JSONEncoder().encode(days), forKey: key)
    }

    /// First run with stats: start from whatever History still has.
    private static func backfill() -> [String: Day] {
        var days: [String: Day] = [:]
        for record in HistoryStore.load() where !record.failed {
            var day = days[dayKey(record.date)] ?? Day()
            day.words += record.wordCount
            day.dictations += 1
            day.seconds += record.duration
            days[dayKey(record.date)] = day
        }
        save(days)
        return days
    }
}
