//
//  AudioComponents.swift
//  FolioMind
//
//  Enhanced audio UI components with level meters, waveforms, and controls
//

import SwiftUI
import AVFoundation

// MARK: - Audio Level Meter

struct AudioLevelMeterView: View {
    let level: Float
    let barCount: Int = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(for: index))
                    .frame(width: 3, height: barHeight(for: index))
                    .opacity(shouldHighlight(index: index) ? 1.0 : 0.3)
            }
        }
        .frame(height: 24)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let position = CGFloat(index) / CGFloat(barCount - 1)
        let baseHeight: CGFloat = 8
        let maxHeight: CGFloat = 24
        return baseHeight + (maxHeight - baseHeight) * sin(position * .pi)
    }

    private func shouldHighlight(index: Int) -> Bool {
        let threshold = CGFloat(index) / CGFloat(barCount)
        return CGFloat(level) >= threshold
    }

    private func barColor(for index: Int) -> Color {
        let position = CGFloat(index) / CGFloat(barCount - 1)
        if position < 0.6 {
            return .green
        } else if position < 0.85 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Recording Controls

struct RecordingControlsView: View {
    @ObservedObject var audioRecorder: AudioRecorderService
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Audio level meter
            if audioRecorder.isRecording && !audioRecorder.isPaused {
                AudioLevelMeterView(level: audioRecorder.audioLevel)
                    .padding(.horizontal, 8)
            }

            // Duration display
            Text(formatDuration(audioRecorder.currentDuration))
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundStyle(audioRecorder.isPaused ? .orange : .primary)

            // Control buttons
            HStack(spacing: 20) {
                // Pause/Resume button
                Button {
                    if audioRecorder.isPaused {
                        audioRecorder.resumeRecording()
                    } else {
                        audioRecorder.pauseRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(audioRecorder.isPaused ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                            .frame(width: 56, height: 56)
                        Image(systemName: audioRecorder.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(audioRecorder.isPaused ? .green : .orange)
                    }
                }
                .buttonStyle(.plain)

                // Stop button
                Button {
                    onStop()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.15))
                            .frame(width: 64, height: 64)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.red)
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
            }

            if audioRecorder.isPaused {
                Text("Paused")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Enhanced Playback Controls

struct EnhancedPlaybackControlsView: View {
    @ObservedObject var audioPlayer: AudioPlayerService
    let note: AudioNote
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            // Seek slider
            if !compact {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { audioPlayer.currentTime },
                            set: { audioPlayer.seek(to: $0) }
                        ),
                        in: 0...max(audioPlayer.duration, 1)
                    )
                    .tint(.blue)

                    HStack {
                        Text(formatTime(audioPlayer.currentTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("-\(formatTime(audioPlayer.duration - audioPlayer.currentTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Playback controls
            HStack(spacing: compact ? 16 : 24) {
                if !compact {
                    // Skip back button
                    Button {
                        audioPlayer.skipBackward()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(audioPlayer.currentTime < 1)
                }

                // Play/pause button
                Button {
                    if isPlayingThisNote {
                        if audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.resume()
                        }
                    } else {
                        do {
                            try audioPlayer.play(url: URL(fileURLWithPath: note.fileURL), noteID: note.id)
                        } catch {
                            print("Playback error: \(error)")
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPlayingThisNote && audioPlayer.isPlaying ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                            .frame(width: compact ? 40 : 56, height: compact ? 40 : 56)
                        Image(systemName: isPlayingThisNote && audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: compact ? 16 : 22, weight: .bold))
                            .foregroundStyle(isPlayingThisNote && audioPlayer.isPlaying ? .green : .blue)
                    }
                }
                .buttonStyle(.plain)

                if !compact {
                    // Skip forward button
                    Button {
                        audioPlayer.skipForward()
                    } label: {
                        Image(systemName: "goforward.15")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(audioPlayer.currentTime >= audioPlayer.duration - 1)
                }
            }

            // Playback speed control
            if !compact {
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button {
                            audioPlayer.setPlaybackRate(Float(speed))
                        } label: {
                            HStack {
                                Text("\(speed, specifier: "%.2g")×")
                                if abs(audioPlayer.playbackRate - Float(speed)) < 0.01 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.caption)
                        Text("\(audioPlayer.playbackRate, specifier: "%.2g")×")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var isPlayingThisNote: Bool {
        audioPlayer.currentNoteID == note.id
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Tag Management View

struct TagManagementView: View {
    @Binding var tags: [String]
    @State private var newTag: String = ""
    @State private var editingTag: String?
    @State private var editedTagText: String = ""
    @State private var isAddingTag: Bool = false
    @FocusState private var addFieldFocused: Bool
    @FocusState private var focusedEditTag: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation {
                        isAddingTag = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        addFieldFocused = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
            }

            if tags.isEmpty && !isAddingTag {
                Text("No tags yet. Tap 'Add' to create one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }

            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        if editingTag == tag {
                            EditableTagChip(
                                text: $editedTagText,
                                focused: $focusedEditTag,
                                tagId: tag,
                                onSave: {
                                    saveEditedTag(original: tag)
                                },
                                onCancel: {
                                    editingTag = nil
                                    editedTagText = ""
                                }
                            )
                        } else {
                            TagChip(
                                text: tag,
                                onEdit: {
                                    editingTag = tag
                                    editedTagText = tag
                                    focusedEditTag = tag
                                },
                                onDelete: {
                                    withAnimation {
                                        tags.removeAll { $0 == tag }
                                    }
                                }
                            )
                        }
                    }
                }
            }

            if isAddingTag {
                HStack(spacing: 8) {
                    TextField("Tag name", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .focused($addFieldFocused)
                        .onSubmit {
                            addTag()
                        }
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    Button("Add") {
                        addTag()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    .controlSize(.small)

                    Button("Cancel") {
                        newTag = ""
                        isAddingTag = false
                        addFieldFocused = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAddingTag)
        .animation(.easeInOut(duration: 0.2), value: editingTag)
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && !tags.contains(trimmed) {
            withAnimation {
                tags.append(trimmed)
            }
            newTag = ""
            isAddingTag = false
            addFieldFocused = false
        }
    }

    private func saveEditedTag(original: String) {
        let trimmed = editedTagText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty && trimmed != original && !tags.contains(trimmed) {
            if let index = tags.firstIndex(of: original) {
                tags[index] = trimmed
            }
        }
        editingTag = nil
        editedTagText = ""
    }
}

struct TagChip: View {
    let text: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text)

            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.12))
        )
    }
}

struct EditableTagChip: View {
    @Binding var text: String
    @FocusState.Binding var focused: String?
    let tagId: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            TextField("Tag", text: $text)
                .textFieldStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .focused($focused, equals: tagId)
                .onSubmit {
                    onSave()
                }
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .frame(minWidth: 40)

            Button {
                onSave()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.blue.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(Color.blue, lineWidth: 1.5)
                )
        )
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            let placement = result.positions[index]
            subview.place(
                at: CGPoint(
                    x: bounds.minX + placement.x,
                    y: bounds.minY + placement.y
                ),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: currentX, y: currentY))
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
}

// MARK: - Bookmark List View

struct BookmarkListView: View {
    @Binding var bookmarks: [AudioBookmark]
    let isPlaying: Bool
    let currentTime: TimeInterval
    let onSeek: (TimeInterval) -> Void
    let onAddBookmark: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bookmarks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onAddBookmark()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bookmark.fill")
                        Text("Add")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPlaying ? .blue : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(!isPlaying)
                .opacity(isPlaying ? 1.0 : 0.5)
            }

            if bookmarks.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No bookmarks yet")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    if !isPlaying {
                        Text("Play the recording to add bookmarks")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            } else {
                ForEach(bookmarks.sorted(by: { $0.timestamp < $1.timestamp })) { bookmark in
                    BookmarkRow(
                        bookmark: bookmark,
                        onTap: {
                            onSeek(bookmark.timestamp)
                        },
                        onDelete: {
                            bookmarks.removeAll { $0.id == bookmark.id }
                        }
                    )
                }
            }
        }
    }
}

struct BookmarkRow: View {
    let bookmark: AudioBookmark
    let onTap: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onTap()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(formatTimestamp(bookmark.timestamp))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                    Text(bookmark.note)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private func formatTimestamp(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
