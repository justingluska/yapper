import SwiftUI

/// Your dictation stats: totals, and a contribution grid of the last 20
/// weeks, one square per day, darker for more words.
struct StatsView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var days: [String: StatsStore.Day] = [:]

    private static let weeks = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                tile(totalWords.formatted(), "words")
                tile(totalDictations.formatted(), "dictations")
                tile(minutesLabel(spokenSeconds / 60), "spoken")
                tile(minutesLabel(savedMinutes), "saved vs typing")
                tile(wordsPerMinute > 0 ? "\(wordsPerMinute)" : "–", "words per minute")
                tile("\(streak)", streak == 1 ? "day streak" : "day streak")
            }

            VStack(alignment: .leading, spacing: 8) {
                ContributionGrid(levels: levels, weeks: Self.weeks)
                HStack(spacing: 4) {
                    Text("Last \(Self.weeks) weeks")
                    Spacer()
                    Text("Less")
                    ForEach(0..<5) { level in
                        RoundedRectangle(cornerRadius: 2).fill(ContributionGrid.color(level)).frame(width: 10, height: 10)
                    }
                    Text("More")
                }
                .font(Theme.font(11))
                .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.vertical, 8)
        .onAppear { days = StatsStore.load() }
        .onChange(of: controller.historyVersion) { _, _ in days = StatsStore.load() }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.display(22))
                .foregroundStyle(Theme.textEmphasis)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.font(12))
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Numbers

    private var totalWords: Int { days.values.reduce(0) { $0 + $1.words } }
    private var totalDictations: Int { days.values.reduce(0) { $0 + $1.dictations } }
    private var spokenSeconds: Double { days.values.reduce(0) { $0 + $1.seconds } }

    private var wordsPerMinute: Int {
        spokenSeconds >= 10 ? Int((Double(totalWords) / (spokenSeconds / 60)).rounded()) : 0
    }

    /// Typing on a phone runs about 40 words a minute.
    private var savedMinutes: Double {
        max(0, Double(totalWords) / 40 - spokenSeconds / 60)
    }

    private func minutesLabel(_ minutes: Double) -> String {
        if minutes < 1 { return minutes > 0 ? "<1 min" : "0 min" }
        if minutes < 60 { return "\(Int(minutes.rounded())) min" }
        return String(format: "%.1f h", minutes / 60)
    }

    /// Consecutive days with a dictation, ending today (or yesterday, so the
    /// streak doesn't read 0 first thing in the morning).
    private var streak: Int {
        let calendar = Calendar.current
        var date = Date()
        if (days[StatsStore.dayKey(date)]?.dictations ?? 0) == 0 {
            date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        var count = 0
        while (days[StatsStore.dayKey(date)]?.dictations ?? 0) > 0 {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return count
    }

    /// 0...4 for each day of the grid, oldest first, column by column (a
    /// column is a week, Sunday on top). Days after today are -1.
    private var levels: [Int] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today) - calendar.firstWeekday
        let offset = (weekday + 7) % 7
        guard let start = calendar.date(byAdding: .day, value: -(Self.weeks * 7 - 1 - (6 - offset)), to: today) else { return [] }
        let words = (0..<(Self.weeks * 7)).map { index -> Int? in
            guard let date = calendar.date(byAdding: .day, value: index, to: start), date <= today else { return nil }
            return days[StatsStore.dayKey(date)]?.words ?? 0
        }
        let busiest = max(1, words.compactMap { $0 }.max() ?? 1)
        return words.map { value in
            guard let value else { return -1 }
            if value == 0 { return 0 }
            return min(4, 1 + Int(Double(value) / Double(busiest) * 3.999))
        }
    }
}

struct ContributionGrid: View {
    let levels: [Int]
    let weeks: Int

    static func color(_ level: Int) -> Color {
        switch level {
        case 1: return Theme.ready.opacity(0.3)
        case 2: return Theme.ready.opacity(0.55)
        case 3: return Theme.ready.opacity(0.8)
        case 4: return Theme.ready
        default: return Theme.fillInput
        }
    }

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 3
            let size = (geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks)
            HStack(alignment: .top, spacing: gap) {
                ForEach(0..<weeks, id: \.self) { week in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { day in
                            let index = week * 7 + day
                            let level = index < levels.count ? levels[index] : -1
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(level < 0 ? Color.clear : Self.color(level))
                                .frame(width: size, height: size)
                        }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(weeks) / 7, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Dictation activity for the last \(weeks) weeks")
    }
}
