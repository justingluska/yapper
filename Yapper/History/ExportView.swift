import SwiftUI

/// Export options: which dictations (from Settings), the format, and whether
/// the recordings go along. Sharing goes through the iOS share sheet, so
/// AirDrop, Save to Files, Messages and Mail all work.
struct ExportView: View {
    /// What can be exported: everything (Settings) or a selection (History).
    let records: [DictationRecord]
    /// Settings offers a date range; a selection is already what you want.
    var offersRange = false

    @Environment(\.dismiss) private var dismiss
    @State private var range: ExportRange = .all
    @State private var format: HistoryExport.Format = .text
    @State private var includeRecordings = false
    @State private var working = false
    @State private var failure: String?

    private var chosen: [DictationRecord] {
        offersRange ? records.filter { range.contains($0.date) } : records
    }

    /// Recordings among `chosen`, worked out when the range changes.
    @State private var recordings: (count: Int, bytes: Int64) = (0, 0)

    var body: some View {
        NavigationStack {
            Form {
                if offersRange {
                    Section {
                        Picker("Dictations", selection: $range) {
                            ForEach(ExportRange.allCases) { range in
                                Text(range.title).tag(range)
                            }
                        }
                    } header: {
                        SectionLabel(text: "Which")
                    }
                }

                Section {
                    ForEach(HistoryExport.Format.allCases) { option in
                        Button {
                            format = option
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .font(Theme.font(16, .medium))
                                        .foregroundStyle(Theme.textEmphasis)
                                    Text(option.detail)
                                        .font(Theme.font(13))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                if option == format {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Theme.textEmphasis)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(option == format ? .isSelected : [])
                    }
                } header: {
                    SectionLabel(text: "Format")
                }

                Section {
                    Toggle("Include recordings", isOn: $includeRecordings)
                        .disabled(recordings.count == 0)
                } footer: {
                    Text(recordingsFooter)
                }
            }
            .font(Theme.font(16))
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Text(summary)
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.textMuted)
                    Button(action: export) {
                        if working {
                            ProgressView().tint(Theme.onPrimary)
                        } else {
                            Text(chosen.isEmpty ? "Nothing to export" : "Export")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(chosen.isEmpty || working)
                    .accessibilityIdentifier("export.share")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(Theme.background)
            }
            .navigationTitle("Export")
            .onAppear { recordings = RecordingStore.summary(of: chosen) }
            .onChange(of: range) { _, _ in
                recordings = RecordingStore.summary(of: chosen)
                if recordings.count == 0 { includeRecordings = false }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Couldn't export", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private var summary: String {
        let dictations = chosen.count == 1 ? "1 dictation" : "\(chosen.count) dictations"
        guard includeRecordings, recordings.count > 0 else { return dictations }
        let files = recordings.count == 1 ? "1 recording" : "\(recordings.count) recordings"
        return "\(dictations) and \(files) (\(recordings.bytes.formatted(.byteCount(style: .file))))"
    }

    private var recordingsFooter: String {
        if recordings.count == 0 {
            return "None of these dictations has a recording kept (Settings › Keep recordings)."
        }
        let files = recordings.count == 1 ? "1 recording" : "\(recordings.count) recordings"
        return "\(files), \(recordings.bytes.formatted(.byteCount(style: .file))). Each is an audio file next to the export. For a new iPhone, pick JSON and include recordings, then import both there."
    }

    private func export() {
        working = true
        let records = chosen
        let format = format
        let withAudio = includeRecordings
        Task {
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try HistoryTransfer.prepare(records, as: format, includeRecordings: withAudio)
                }.value
                working = false
                ShareSheet.present(files) { shared in
                    HistoryTransfer.cleanUp(files)
                    if shared { dismiss() }
                }
            } catch {
                working = false
                failure = error.localizedDescription
            }
        }
    }
}

/// Settings › Export history: how far back to go.
enum ExportRange: String, CaseIterable, Identifiable {
    case today, week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        case .all: return "All"
        }
    }

    func contains(_ date: Date, now: Date = Date()) -> Bool {
        switch self {
        case .today: return Calendar.current.isDate(date, inSameDayAs: now)
        case .week: return date >= now.addingTimeInterval(-7 * 86_400)
        case .month: return date >= now.addingTimeInterval(-30 * 86_400)
        case .all: return true
        }
    }
}
