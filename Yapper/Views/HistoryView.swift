import AVFoundation
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var records: [DictationRecord] = []
    @State private var query = ""
    @State private var selected: DictationRecord?
    /// Select mode: tap rows to pick several, then share, copy or delete them.
    @State private var selecting = false
    @State private var selection: Set<UUID> = []
    @State private var exporting: ExportRequest?
    @State private var confirmDeleteSelected = false
    @State private var toast: String?

    private var filtered: [DictationRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { $0.text.localizedCaseInsensitiveContains(query) || ($0.error ?? "").localizedCaseInsensitiveContains(query) }
    }

    /// In the order History shows them.
    private var selectedRecords: [DictationRecord] {
        records.filter { selection.contains($0.id) }
    }

    /// Select All covers what's showing, so a search can narrow it first.
    private var allSelected: Bool {
        !filtered.isEmpty && filtered.allSatisfy { selection.contains($0.id) }
    }

    var body: some View {
        List {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing yet")
                        .font(Theme.font(17, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text("Every dictation is kept here on your iPhone, including ones that failed, so nothing you say is lost. Recordings are kept for 30 days by default so you can play them back or transcribe them again. Change both in Settings.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(filtered) { record in
                Button {
                    if selecting { toggle(record) } else { selected = record }
                } label: {
                    HStack(spacing: 12) {
                        if selecting {
                            let on = selection.contains(record.id)
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 22))
                                .foregroundStyle(on ? Theme.textEmphasis : Theme.textFaint)
                                .accessibilityHidden(true)
                        }
                        HistoryRow(record: record)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selecting && selection.contains(record.id) ? .isSelected : [])
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.hairline)
                .contextMenu {
                    if !selecting {
                        if !record.failed {
                            Button("Copy", systemImage: "doc.on.doc") { copy(record) }
                            Button("Share", systemImage: "square.and.arrow.up") { ShareSheet.present([record.text]) }
                        }
                        Button("Details", systemImage: "info.circle") { selected = record }
                        Button("Select", systemImage: "checkmark.circle") { startSelecting(with: record) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete([record]) }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if !selecting {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete([record]) }
                            .tint(Theme.recording)
                        if !record.failed {
                            Button("Share", systemImage: "square.and.arrow.up") { ShareSheet.present([record.text]) }
                                .tint(.gray)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    if !selecting, !record.failed {
                        Button("Copy", systemImage: "doc.on.doc") { copy(record) }
                            .tint(Theme.ready)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search history")
        .navigationTitle("History")
        .toolbar { toolbar }
        .toolbar(selecting ? .hidden : .visible, for: .tabBar)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(Theme.font(14, .medium))
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.primary))
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .alert(deleteSelectedTitle, isPresented: $confirmDeleteSelected) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                delete(selectedRecords)
                selection = []
                if records.isEmpty { selecting = false }
            }
        } message: {
            Text("Their recordings go too. Your stats stay. This can't be undone.")
        }
        .sheet(item: $selected) { record in
            DictationDetailView(record: record) {
                delete([record])
                selected = nil
            }
            .environmentObject(controller)
            // Full height: a long dictation reads to its last word, with the
            // details under it, instead of being cut off at half height.
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $exporting) { request in
            ExportView(records: request.records)
        }
        .onAppear {
            reload()
            reveal()
        }
        .onChange(of: controller.historyVersion) { _, _ in reload() }
        .onChange(of: controller.revealRecord) { _, _ in reveal() }
    }

    /// Opens the hands-free dictation Yapper saved in the background.
    private func reveal() {
        guard let id = controller.revealRecord else { return }
        controller.revealRecord = nil
        reload()
        guard let record = records.first(where: { $0.id == id }) else { return }
        selecting = false
        selection = []
        selected = record
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .topBarLeading) {
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selection.subtract(filtered.map(\.id))
                    } else {
                        selection.formUnion(filtered.map(\.id))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    selecting = false
                    selection = []
                }
                .fontWeight(.semibold)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    exporting = ExportRequest(records: selectedRecords)
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("history.selection.share")
                Spacer()
                Text(selection.isEmpty ? "Select dictations" : "\(selection.count) selected")
                    .font(Theme.font(13, .medium))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize()
                Spacer()
                Button {
                    copySelected()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!selectedRecords.contains { !$0.failed })
                .accessibilityIdentifier("history.selection.copy")
                Button(role: .destructive) {
                    confirmDeleteSelected = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Theme.recording)
                .disabled(selection.isEmpty)
                .accessibilityIdentifier("history.selection.delete")
            }
        } else if !records.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { selecting = true }
            }
        }
    }

    private var deleteSelectedTitle: String {
        selection.count == 1 ? "Delete 1 dictation?" : "Delete \(selection.count) dictations?"
    }

    private func reload() {
        records = HistoryStore.load()
        // Forget anything that's no longer in History.
        selection.formIntersection(records.map(\.id))
        if records.isEmpty { selecting = false }
    }

    private func toggle(_ record: DictationRecord) {
        if selection.contains(record.id) {
            selection.remove(record.id)
        } else {
            selection.insert(record.id)
        }
    }

    private func startSelecting(with record: DictationRecord) {
        selecting = true
        selection = [record.id]
    }

    private func copy(_ record: DictationRecord) {
        Clipboard.copy(record.text)
        show("Copied")
    }

    /// The selected dictations' text, one paragraph each, in History's order.
    private func copySelected() {
        let texts = selectedRecords.filter { !$0.failed }.map(\.text)
        guard !texts.isEmpty else { return }
        Clipboard.copy(texts.joined(separator: "\n\n"))
        Haptics.success()
        show(texts.count == 1 ? "Copied 1 dictation" : "Copied \(texts.count) dictations")
    }

    /// A short note at the bottom of the screen, gone after a moment.
    private func show(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private func delete(_ doomed: [DictationRecord]) {
        let ids = Set(doomed.map(\.id))
        records.removeAll { ids.contains($0.id) }
        HistoryStore.save(records)
        RecordingStore.prune()
        controller.historyChanged()
    }
}

/// The dictations Export was opened for.
private struct ExportRequest: Identifiable {
    let id = UUID()
    let records: [DictationRecord]
}

private struct HistoryRow: View {
    let record: DictationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = record.error {
                Label("Failed: \(error)", systemImage: "exclamationmark.triangle")
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.errorFg)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else {
                Text(record.text)
                    .font(Theme.font(15))
                    .foregroundStyle(Theme.textEmphasis)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            HStack(spacing: 6) {
                Text(record.date.formatted(.relative(presentation: .named)))
                Text("·")
                Text(record.engineLabel)
                if RecordingStore.exists(record.audioFile) {
                    Text("·")
                    Image(systemName: "waveform")
                        .accessibilityLabel("Recording saved")
                }
            }
            .font(Theme.font(12))
            .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Everything about one dictation: what transcribed it and why, its
/// recording, and a way to transcribe it again.
struct DictationDetailView: View {
    @EnvironmentObject private var controller: DictationController
    @State var record: DictationRecord
    let onDelete: () -> Void
    @State private var copied = false
    @State private var showDetails = false
    @State private var detailsCopied = false
    @State private var shareError: String?
    @StateObject private var player = RecordingPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let error = record.error {
                        Text(error)
                            .font(Theme.font(16))
                            .foregroundStyle(Theme.errorFg)
                    } else {
                        Text(record.text)
                            .font(Theme.font(17))
                            .foregroundStyle(Theme.textEmphasis)
                            .textSelection(.enabled)

                        HStack(spacing: 10) {
                            Button(copied ? "Copied" : "Copy") {
                                Clipboard.copy(record.text)
                                copied = true
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            share
                        }
                    }

                    recording

                    VStack(alignment: .leading, spacing: 0) {
                        if !record.failed { row("Words", "\(record.wordCount)") }
                        row("Engine", record.engineLabel)
                        if let model = record.model { row("Model", model) }
                        row("Audio", String(format: "%.1f s", record.duration))
                        if let time = record.processingTime {
                            row("Transcribed in", String(format: "%.2f s", time))
                        }
                        row("When", record.date.formatted(date: .abbreviated, time: .shortened))
                    }

                    if let languages = record.languages, !record.failed {
                        LanguageBreakdownView(breakdown: languages, duration: record.duration)
                    }

                    if let kind = record.engineKind, !record.failed {
                        Text(kind.explanation)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.textMuted)
                    }
                    if let note = record.note {
                        Text(note)
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.textMuted)
                    }

                    if !record.raw.isEmpty, record.raw != record.text {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: "Before cleanup")
                            Text(record.raw)
                                .font(Theme.font(15))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                        }
                    }

                    details

                    Button("Delete", role: .destructive, action: onDelete)
                        .font(Theme.font(15, .medium))
                        .foregroundStyle(Theme.errorFg)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(record.failed ? "Failed dictation" : "Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { player.stop() }
            .alert("Couldn't share the recording", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(shareError ?? "")
            }
        }
    }

    /// Everything Yapper knows about how this dictation ran, as plain text
    /// to copy into a bug report. Nothing leaves the iPhone unless the user
    /// pastes it somewhere.
    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { showDetails.toggle() }
            } label: {
                HStack {
                    SectionLabel(text: "Details")
                    Spacer()
                    Text(showDetails ? "Hide" : "Show")
                        .font(Theme.font(13, .medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showDetails {
                Text(record.debugReport)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fillInput))
                Button(detailsCopied ? "Copied" : "Copy details") {
                    Clipboard.copy(record.debugReport)
                    detailsCopied = true
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    /// Share the text, or (while it's kept) the recording.
    @ViewBuilder
    private var share: some View {
        if RecordingStore.exists(record.audioFile) {
            Menu {
                Button("Text", systemImage: "text.alignleft") { ShareSheet.present([record.text]) }
                Button("Recording", systemImage: "waveform") { shareRecording() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(Theme.font(16, .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fillInput))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.borderInput))
            }
        } else {
            Button {
                ShareSheet.present([record.text])
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }

    private func shareRecording() {
        player.stop()
        do {
            let file = try HistoryTransfer.prepareRecording(of: record)
            ShareSheet.present([file]) { _ in HistoryTransfer.cleanUp([file]) }
        } catch {
            shareError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var recording: some View {
        if let file = record.audioFile, RecordingStore.exists(file) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Recording")
                HStack(spacing: 10) {
                    Button {
                        player.toggle(file)
                    } label: {
                        Label(player.playing ? "Stop" : "Play", systemImage: player.playing ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Menu {
                        ForEach(redoChoices) { choice in
                            Button("With \(choice.title)") { redo(choice) }
                        }
                    } label: {
                        Label("Transcribe again", systemImage: "arrow.clockwise")
                            .font(Theme.font(16, .medium))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
                            .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(Theme.fillInput))
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.borderInput))
                    }
                    .disabled(controller.retranscribing)
                }
                if controller.retranscribing {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(controller.modelState == .loading ? "Loading \(ModelChoice.current.title)…" : "Transcribing…")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Text("Kept on this iPhone only, for as long as Settings › Keep recordings says. The new text replaces this entry and is copied.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.textFaint)
            }
        } else {
            Text("The recording isn't kept anymore (Settings › Keep recordings), so this can't be transcribed again.")
                .font(Theme.font(13))
                .foregroundStyle(Theme.textFaint)
        }
    }

    /// The selected model (when it's a downloaded Parakeet model) and Apple.
    private var redoChoices: [ModelChoice] {
        var choices: [ModelChoice] = []
        let current = ModelChoice.current
        if current.isParakeet, Transcriber.isDownloaded(current) { choices.append(current) }
        choices.append(.apple)
        return choices
    }

    private func redo(_ choice: ModelChoice) {
        player.stop()
        Task {
            record = await controller.retranscribe(record, using: choice)
            copied = false
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(Theme.textMuted)
                Spacer()
                Text(value).foregroundStyle(Theme.textEmphasis)
            }
            .font(Theme.font(15))
            .padding(.vertical, 10)
            Hairline()
        }
    }
}

extension DictationRecord {
    /// How this dictation ran, for Details: the app, the settings now, the
    /// engine, and for two languages what each model heard and how the
    /// parts were chosen.
    var debugReport: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        func time(_ seconds: Double) -> String { String(format: "%.1f s", seconds) }
        func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
        var lines = [
            "Yapper \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "When: \(date.formatted(.iso8601))",
            "Engine: \(engine)\(model.map { " · \($0)" } ?? "")",
            "Audio: \(time(duration))\(processingTime.map { " · transcribed in \(String(format: "%.2f s", $0))" } ?? "")",
            "This \(Device.name)'s language: \(Locale.current.identifier)",
            "Speech model now: \(ModelChoice.current.title)",
            "Second language now: \(Settings.secondLanguage ?? "none")",
        ]
        if let note { lines.append("Note: \(note)") }
        if let error { lines.append("Error: \(error)") }
        if let languages {
            lines.append("")
            lines.append("Two languages: \(languages.languages.joined(separator: " + ")) · \(languages.method.rawValue) · \(languages.passes) passes"
                         + (languages.keptWhole.map { " · kept whole in \($0)" } ?? ""))
            for heard in languages.heard ?? [] {
                lines.append("Heard by \(heard.language) alone (\(percent(heard.confidence)) sure): \(heard.text)")
            }
            for part in languages.parts {
                lines.append(String(format: "Part %.1f–%.1f s ", part.start, part.end)
                             + "\(part.language) (\(percent(part.confidence)) sure): \(part.text)")
            }
        } else if Settings.secondLanguage != nil, error == nil {
            lines.append("Two languages: not used for this dictation")
        }
        lines.append("")
        lines.append("Before cleanup: \(raw)")
        lines.append("Text: \(text)")
        return lines.joined(separator: "\n")
    }
}

/// How a dictation in two languages was split: a timeline of which
/// language each part was in, the parts, and how Yapper decided.
struct LanguageBreakdownView: View {
    let breakdown: LanguageBreakdown
    let duration: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Languages")
            timeline
            HStack(spacing: 14) {
                ForEach(breakdown.languages, id: \.self) { language in
                    HStack(spacing: 6) {
                        Circle().fill(color(language)).frame(width: 8, height: 8)
                        Text(name(language))
                    }
                }
            }
            .font(Theme.font(13))
            .foregroundStyle(Theme.textMuted)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(breakdown.parts.enumerated()), id: \.offset) { _, part in
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color(part.language))
                            .frame(width: 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(time(part.start))–\(time(part.end)) · \(name(part.language)) · \(Int((part.confidence * 100).rounded()))% sure")
                                .font(Theme.font(12))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textMuted)
                            Text(part.text)
                                .font(Theme.font(15))
                                .foregroundStyle(Theme.text)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }

            Text(summary)
                .font(Theme.font(14))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The recording as a bar, each part in its language's color.
    private var timeline: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.fillInput)
                ForEach(Array(breakdown.parts.enumerated()), id: \.offset) { _, part in
                    let total = max(duration, breakdown.parts.map(\.end).max() ?? 0, 0.1)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(part.language))
                        .frame(width: max(2, geometry.size.width * (part.end - part.start) / total))
                        .offset(x: geometry.size.width * part.start / total)
                }
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    private var summary: String {
        let names = breakdown.languages.map(name)
        let both = names.joined(separator: " and ")
        let passes = "Apple's model listened \(breakdown.passes) times in all, on this iPhone."
        switch breakdown.method {
        case .windows:
            if let kept = breakdown.keptWhole {
                return "Yapper listened in \(both) and found what might be a switch, but Apple's model was surer of the whole dictation in \(name(kept)), so it kept that. \(passes)"
            }
            if breakdown.parts.count < 2 {
                return "Yapper listened in \(both) and heard only \(breakdown.parts.first.map { name($0.language) } ?? names[0]). \(passes)"
            }
            return "Yapper listened in \(both), cut the recording into short windows, gave each window to the language whose model was surer of it, then transcribed each stretch in its own language. \(passes)"
        case .script:
            let base = breakdown.parts.first.map(\.language) ?? breakdown.languages[0]
            let other = breakdown.languages.first { $0 != base } ?? breakdown.languages[1]
            let switches = breakdown.parts.filter { $0.language == other }.count
            if switches == 0 {
                return "Yapper listened in \(both) and heard only \(name(base)). \(passes)"
            }
            return "\(name(base))'s model writes the \(name(other)) it hears in Latin letters, often misspelled. Yapper had the \(name(other)) model redo those parts (\(switches) here) and kept its words where it was sure of them. \(passes)"
        }
    }

    private func name(_ language: String) -> String {
        Locale.current.localizedString(forIdentifier: language) ?? language
    }

    /// This iPhone's language in gray, the second language in blue.
    private func color(_ language: String) -> Color {
        language == breakdown.languages.first ? Theme.textFaint : Theme.ready
    }

    private func time(_ seconds: Double) -> String {
        String(format: "%d:%04.1f", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60))
    }
}

/// Plays a saved recording.
@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    private var player: AVAudioPlayer?

    func toggle(_ file: String) {
        if playing {
            stop()
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: RecordingStore.url(for: file))
            player.delegate = self
            // Plays alongside a live mic session; otherwise take the speaker.
            if AVAudioSession.sharedInstance().category != .playAndRecord {
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            player.play()
            self.player = player
            playing = true
        } catch {
            playing = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playing = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

struct DictionaryView: View {
    @State private var entries = Settings.replacements
    @State private var spoken = ""
    @State private var written = ""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("When you say a phrase, Yapper writes what you choose instead. Good for names, brands and jargon the model spells wrong.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.textMuted)
                    field("When I say…", text: $spoken)
                    field("Write…", text: $written)
                    Button("Add") { add() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(spoken.trimmingCharacters(in: .whitespaces).isEmpty || written.isEmpty)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Theme.background)

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.spoken).foregroundStyle(Theme.textMuted)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textFaint)
                            Text(entry.written).foregroundStyle(Theme.textEmphasis)
                        }
                        .font(Theme.font(15))
                    }
                    .onDelete { offsets in
                        entries.remove(atOffsets: offsets)
                        Settings.replacements = entries
                    }
                    .listRowBackground(Theme.background)
                } header: {
                    SectionLabel(text: "Your words")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Dictionary")
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(Theme.font(15))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 12)
            .frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Theme.fillInput))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Theme.borderInput))
    }

    private func add() {
        let entry = Replacement(spoken: spoken.trimmingCharacters(in: .whitespaces), written: written)
        entries.insert(entry, at: 0)
        Settings.replacements = entries
        spoken = ""
        written = ""
    }
}
