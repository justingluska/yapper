import SwiftUI

struct HistoryPane: View {
    @EnvironmentObject private var dictation: MacDictation
    @State private var records: [DictationRecord] = []
    @State private var search = ""
    @State private var confirmDeleteAll = false
    @State private var copied: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                PageTitle(title: "History", subtitle: summary)
                if !records.isEmpty {
                    SmallButton(title: "Delete all") { confirmDeleteAll = true }
                }
            }
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .font(Theme.font(13))
            if filtered.isEmpty {
                Spacer()
                Text(records.isEmpty ? "Your dictations show up here." : "Nothing matches.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filtered) { record in
                            row(record)
                            Hairline()
                        }
                    }
                }
            }
        }
        .padding(28)
        .onAppear(perform: reload)
        .onChange(of: dictation.historyVersion) { _, _ in reload() }
        .confirmationDialog("Delete every dictation and recording on this Mac?", isPresented: $confirmDeleteAll) {
            Button("Delete all", role: .destructive) { dictation.deleteAllHistory() }
        }
    }

    private var filtered: [DictationRecord] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return records }
        return records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private var summary: String {
        let words = records.reduce(0) { $0 + $1.wordCount }
        return records.isEmpty ? "Nothing yet" : "\(records.count) dictations · \(words) words"
    }

    private func reload() {
        records = HistoryStore.load()
    }

    private func row(_ record: DictationRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.failed ? (record.error ?? "Failed") : record.text)
                    .font(Theme.font(13))
                    .foregroundStyle(record.failed ? Theme.errorFg : Theme.textEmphasis)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(String(format: "%.0f", record.duration)) s · \(record.engineLabel)")
                    .font(Theme.font(11))
                    .foregroundStyle(Theme.textFaint)
            }
            Spacer(minLength: 8)
            if !record.failed {
                Button {
                    dictation.copy(record.text)
                    copied = record.id
                } label: {
                    Image(systemName: copied == record.id ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy")
            }
            Button {
                dictation.delete(record)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .padding(.vertical, 12)
    }
}
