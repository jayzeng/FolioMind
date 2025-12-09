//
//  AudioNotesListView.swift
//  FolioMind
//
//  Dedicated audio notes list view with search, filter, and batch operations
//

import SwiftUI
import SwiftData

struct AudioNotesListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var services: AppServices

    @Query(sort: \AudioNote.createdAt, order: .reverse) private var allAudioNotes: [AudioNote]

    @State private var searchText = ""
    @State private var selectedFilter: AudioNoteFilter = .all
    @State private var selectedNotes: Set<UUID> = []
    @State private var showingBatchActions = false
    @State private var noteToShow: AudioNote?
    @State private var errorMessage: String?

    enum AudioNoteFilter: String, CaseIterable {
        case all = "All"
        case favorites = "Favorites"
        case recent = "Recent"
        case tagged = "Tagged"

        var icon: String {
            switch self {
            case .all: return "waveform"
            case .favorites: return "star.fill"
            case .recent: return "clock.fill"
            case .tagged: return "tag.fill"
            }
        }
    }

    private var filteredNotes: [AudioNote] {
        var notes = allAudioNotes

        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .favorites:
            notes = notes.filter { $0.isFavorite }
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            notes = notes.filter { $0.createdAt >= sevenDaysAgo }
        case .tagged:
            notes = notes.filter { !$0.tags.isEmpty }
        }

        // Apply search
        if !searchText.isEmpty {
            notes = notes.filter { note in
                note.title.localizedCaseInsensitiveContains(searchText) ||
                note.transcript?.localizedCaseInsensitiveContains(searchText) == true ||
                note.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }

        return notes
    }

    private var groupedNotes: [(String, [AudioNote])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredNotes) { note -> String in
            if calendar.isDateInToday(note.createdAt) {
                return "Today"
            } else if calendar.isDateInYesterday(note.createdAt) {
                return "Yesterday"
            } else if calendar.isDate(note.createdAt, equalTo: Date(), toGranularity: .weekOfYear) {
                return "This Week"
            } else if calendar.isDate(note.createdAt, equalTo: Date(), toGranularity: .month) {
                return "This Month"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: note.createdAt)
            }
        }

        let order = ["Today", "Yesterday", "This Week", "This Month"]
        return grouped.sorted { a, b in
            if let aIndex = order.firstIndex(of: a.key), let bIndex = order.firstIndex(of: b.key) {
                return aIndex < bIndex
            } else if order.contains(a.key) {
                return true
            } else if order.contains(b.key) {
                return false
            } else {
                return a.key > b.key
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(AudioNoteFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                icon: filter.icon,
                                isSelected: selectedFilter == filter,
                                count: countForFilter(filter)
                            ) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemGroupedBackground))

                if filteredNotes.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(groupedNotes, id: \.0) { section, notes in
                            Section(header: Text(section).font(.subheadline.weight(.semibold))) {
                                ForEach(notes) { note in
                                    AudioNoteListRow(
                                        note: note,
                                        audioPlayer: services.audioPlayer,
                                        isSelected: selectedNotes.contains(note.id),
                                        onTap: {
                                            if showingBatchActions {
                                                toggleSelection(note.id)
                                            } else {
                                                noteToShow = note
                                            }
                                        },
                                        onLongPress: {
                                            showingBatchActions = true
                                            selectedNotes.insert(note.id)
                                        },
                                        onDelete: {
                                            deleteNote(note)
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Audio Notes")
            .searchable(text: $searchText, prompt: "Search notes or transcripts")
            .toolbar {
                if showingBatchActions {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            showingBatchActions = false
                            selectedNotes.removeAll()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button {
                                batchToggleFavorite()
                            } label: {
                                Label("Toggle Favorites", systemImage: "star")
                            }

                            Button(role: .destructive) {
                                batchDelete()
                            } label: {
                                Label("Delete Selected", systemImage: "trash")
                            }
                        } label: {
                            Label("Actions", systemImage: "ellipsis.circle")
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingBatchActions.toggle()
                        } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            .sheet(item: $noteToShow) { note in
                NavigationStack {
                    SimpleAudioNoteDetailView(
                        note: note,
                        audioPlayer: services.audioPlayer,
                        onDelete: {
                            deleteNote(note)
                            noteToShow = nil
                        }
                    )
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            })
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: selectedFilter == .all ? "waveform" : selectedFilter.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            if !searchText.isEmpty {
                Text("Try adjusting your search")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateTitle: String {
        if !searchText.isEmpty {
            return "No notes match your search"
        }
        switch selectedFilter {
        case .all:
            return "No audio notes yet"
        case .favorites:
            return "No favorite notes"
        case .recent:
            return "No recent notes"
        case .tagged:
            return "No tagged notes"
        }
    }

    private func countForFilter(_ filter: AudioNoteFilter) -> Int {
        switch filter {
        case .all:
            return allAudioNotes.count
        case .favorites:
            return allAudioNotes.filter { $0.isFavorite }.count
        case .recent:
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return allAudioNotes.filter { $0.createdAt >= sevenDaysAgo }.count
        case .tagged:
            return allAudioNotes.filter { !$0.tags.isEmpty }.count
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedNotes.contains(id) {
            selectedNotes.remove(id)
        } else {
            selectedNotes.insert(id)
        }
    }

    private func deleteNote(_ note: AudioNote) {
        if services.audioPlayer.currentNoteID == note.id {
            services.audioPlayer.stop()
        }
        let url = URL(fileURLWithPath: note.fileURL)
        modelContext.delete(note)
        try? FileManager.default.removeItem(at: url)
        try? modelContext.save()
    }

    private func batchToggleFavorite() {
        for id in selectedNotes {
            if let note = allAudioNotes.first(where: { $0.id == id }) {
                note.isFavorite.toggle()
            }
        }
        try? modelContext.save()
        showingBatchActions = false
        selectedNotes.removeAll()
    }

    private func batchDelete() {
        for id in selectedNotes {
            if let note = allAudioNotes.first(where: { $0.id == id }) {
                deleteNote(note)
            }
        }
        showingBatchActions = false
        selectedNotes.removeAll()
    }
}

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
                if count > 0 {
                    Text("(\(count))")
                        .font(.caption2)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

struct AudioNoteListRow: View {
    let note: AudioNote
    @ObservedObject var audioPlayer: AudioPlayerService
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if note.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }

                if !note.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(note.tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                            }
                        }
                    }
                }

                Text(note.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatDuration(note.duration))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(perform: onLongPress)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                note.isFavorite.toggle()
            } label: {
                Label(note.isFavorite ? "Unfavorite" : "Favorite", systemImage: note.isFavorite ? "star.slash" : "star")
            }
            .tint(.yellow)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Simple detail view for AudioNotesListView
struct SimpleAudioNoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var note: AudioNote
    @ObservedObject var audioPlayer: AudioPlayerService
    let onDelete: () -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.title)
                        .font(.title3.weight(.semibold))
                    HStack {
                        Label(note.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                        Label(formatDuration(note.duration), systemImage: "timer")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                EnhancedPlaybackControlsView(
                    audioPlayer: audioPlayer,
                    note: note,
                    compact: false
                )
            }

            if let transcript = note.transcript, !transcript.isEmpty {
                Section("Transcript") {
                    Text(transcript)
                        .textSelection(.enabled)
                }
            }

            if let summary = note.summary, !summary.isEmpty {
                Section("Summary") {
                    Text(summary)
                }
            }

            if !note.tags.isEmpty {
                Section("Tags") {
                    ForEach(note.tags, id: \.self) { tag in
                        Text(tag)
                    }
                }
            }
        }
        .navigationTitle("Audio Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Menu {
                    Button {
                        note.isFavorite.toggle()
                        try? modelContext.save()
                    } label: {
                        Label(note.isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: note.isFavorite ? "star.slash" : "star")
                    }

                    ShareLink(item: URL(fileURLWithPath: note.fileURL)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }

                    Divider()

                    Button(role: .destructive) {
                        audioPlayer.stop()
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        formatter.unitsStyle = .short
        return formatter.string(from: duration) ?? "0:00"
    }
}
