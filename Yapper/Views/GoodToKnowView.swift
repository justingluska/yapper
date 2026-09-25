import Foundation
import SwiftUI

/// The honest trade-offs of doing dictation on the phone, in one place:
/// Settings › Good to know, and the short version in onboarding.
struct GoodToKnowList: View {
    /// The short version (onboarding) shows only the first few points.
    var compact = false

    private static let points: [(String, String)] = [
        ("Starting takes a moment",
         "Turning the speech engine on loads the model into your iPhone's Neural Engine: a few seconds usually, and a few minutes the very first time, while iOS optimizes it for your chip. Apple on-device starts instantly."),
        ("It needs space",
         "Parakeet Ultra is a one-time 632 MB download (Parakeet v3 is 480 MB). Apple on-device needs nothing extra."),
        ("Best on recent iPhones",
         "Parakeet runs best on roughly iPhone 12 and newer, especially models with 6 GB of memory or more. Older iPhones work, just slower; Apple on-device is the lighter choice there."),
        ("Yapper opens once per session",
         "iOS never lets a keyboard use the microphone, so the first dictation opens the Yapper app to start listening. Swipe back, and it stays on for the time you pick (5, 15 or 60 minutes)."),
        ("The orange dot and battery",
         "While the engine is on, iOS shows its orange mic dot and the mic stays ready, which uses a little more battery. Turn it off any time from the app, the keyboard or the Dynamic Island."),
        ("Languages",
         "Parakeet understands 25 European languages, English included. Apple on-device uses your iPhone's language."),
        ("Where the keyboard can't go",
         "iOS switches to its own keyboard in password fields, and some apps don't allow other keyboards."),
        ("It can mishear",
         "Names, numbers and jargon can come out wrong. Check before you send, and teach it your words in Dictionary."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(Self.points.prefix(compact ? 3 : Self.points.count).enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 3) {
                    Text(point.0)
                        .font(Theme.font(15, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text(point.1)
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note = DeviceFit.note {
                Text(note)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.warningFg)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct GoodToKnowView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageTitle(title: "Good to know", subtitle: "What comes with doing it all on your iPhone.")
                GoodToKnowList()
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Whether this iPhone is on the light side for Parakeet. Memory is the
/// signal: the model is about 600 MB and has to stay loaded in the
/// background while the engine is on.
enum DeviceFit {
    static var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    static var note: String? {
        guard memoryGB < 5.5 else { return nil }
        return String(format: "This iPhone has about %.0f GB of memory, so Parakeet may be slow to start here. If it feels sluggish, choose Apple on-device in Settings.", memoryGB.rounded())
    }
}
