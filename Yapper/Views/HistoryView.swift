import AVFoundation
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var controller: DictationController
    @State private var records: [DictationRecord] = []
    @State private var query = ""
    @State private var selected: DictationRecord?
    @State private var confirmDeleteAll = false
    @State private var confirmDeleteAllAgain = false

    private var filtered: [DictationRecord] {
        guard !query.isEmpty else { return records }
        return records.filter { $0.text.localizedCaseInsensitiveContains(query) || ($0.error ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing yet")
                        .font(Theme.font(17, .semibold))
                        .foregroundStyle(Theme.textEmphasis)
                    Text("Every dictation is kept here on your iPhone, including ones that failed, so nothing you say is lost. Recordings are kept for a day by default so you can play them back or transcribe them again. Change both in Settings.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.textMuted)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            ForEach(filtered) { record in
                Button { selected = record } label: {
                    HistoryRow(record: record)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.hairline)
                .contextMenu {
                    if !record.failed {
                        Button("Copy", systemImage: "doc.on.doc") { Clipboard.copy(record.text) }
                        ShareLink(item: record.text)
                    }
                    Button("Details", systemImage: "info.circle") { selected = record }
                    Button("Delete", systemImage: "trash", role: .destructive) { delete(record) }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { delete(record) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $query, prompt: "Search history")
        .navigationTitle("History")
        .toolbar {
            if !records.isEmpty {
                Menu {
                    Button("Delete All", systemImage: "trash", role: .destructive) { confirmDeleteAll = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("More")
            }
        }
        // Two separate confirmations: this can't be undone.
        .alert("Delete all history?", isPresented: $confirmDeleteAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { confirmDeleteAllAgain = true }
            }
        } message: {
            Text("This removes all \(records.count) dictations and their recordings from this iPhone. Your stats stay.")
        }
        .alert("Are you sure?", isPresented: $confirmDeleteAllAgain) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Everything", role: .destructive) {
                controller.deleteAllHistory()
                records = []
            }
        } message: {
            Text("There's no undo, and nothing is backed up anywhere else.")
        }
        .sheet(item: $selected) { record in
            DictationDetailView(record: record) {
                delete(record)
                selected = nil
            }
            .environmentObject(controller)
            .presentationDetents([.medium, .large])
        }
        .onAppear { records = HistoryStore.load() }
        .onChange(of: controller.historyVersion) { _, _ in records = HistoryStore.load() }
    }

    private func delete(_ record: DictationRecord) {
        records.removeAll { $0.id == record.id }
        HistoryStore.save(records)
        RecordingStore.prune()
        controller.historyChanged()
    }
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
    @StateObject private var player = RecordingPlayer()

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

                        Button(copied ? "Copied" : "Copy") {
                            Clipboard.copy(record.text)
                            copied = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    recording

                    VStack(alignment: .leading, spacing: 0) {
                        row("Engine", record.engineLabel)
                        if let model = record.model { row("Model", model) }
                        row("Audio", String(format: "%.1f s", record.duration))
                        if let time = record.processingTime {
                            row("Transcribed in", String(format: "%.2f s", time))
                        }
                        row("When", record.date.formatted(date: .abbreviated, time: .shortened))
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

                    Button("Delete", role: .destructive, action: onDelete)
                        .font(Theme.font(15, .medium))
                        .foregroundStyle(Theme.errorFg)
                }
                .padding(20)
            }
            .background(Theme.background)
            .navigationTitle(record.failed ? "Failed dictation" : "Dictation")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { player.stop() }
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
