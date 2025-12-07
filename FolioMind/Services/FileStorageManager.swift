//
//  FileStorageManager.swift
//  FolioMind
//
//  Centralized file storage using App Groups for shared container access.
//

import Foundation

/// Manages file storage in a shared App Group container
final class FileStorageManager {
    enum StorageError: LocalizedError {
        case containerUnavailable
        case directoryCreationFailed(String)
        case fileCopyFailed(String)
        case migrationFailed(String)

        var errorDescription: String? {
            switch self {
            case .containerUnavailable:
                return "Shared container is not available. Ensure App Group is configured."
            case .directoryCreationFailed(let path):
                return "Failed to create directory at \(path)"
            case .fileCopyFailed(let message):
                return "Failed to copy file: \(message)"
            case .migrationFailed(let message):
                return "Failed to migrate files: \(message)"
            }
        }
    }

    enum StorageDirectory: String {
        case assets = "FolioMindAssets"
        case recordings = "FolioMindRecordings"
        case temp = "Temp"
        case database = "FolioMindDatabase"

        var subdirectoryName: String { rawValue }
    }

    // MARK: - App Group Configuration

    /// The App Group identifier matching the bundle identifier.
    /// Format: group.<reverse-domain>.<app-name>
    private static let appGroupIdentifier = "group.com.lz.studio.FolioMind"

    // MARK: - Singleton

    static let shared = FileStorageManager()

    private let fileManager = FileManager.default
    private let useAppGroup: Bool
    private let containerURL: URL

    private init() {
        // Try to get the App Group container
        if let groupURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) {
            self.containerURL = groupURL
            self.useAppGroup = true
            print("✅ Using App Group container: \(groupURL.path)")
        } else {
            // Fallback to Documents directory if App Group is not configured
            do {
                self.containerURL = try fileManager.url(
                    for: .documentDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                self.useAppGroup = false
                print("⚠️ App Group not available, using Documents directory: \(containerURL.path)")
            } catch {
                fatalError("Cannot access Documents directory: \(error)")
            }
        }
    }

    // MARK: - Directory Access

    /// Returns the URL for a specific storage directory, creating it if needed
    func url(for directory: StorageDirectory) throws -> URL {
        let directoryURL = containerURL.appendingPathComponent(directory.subdirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            do {
                try fileManager.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
            } catch {
                throw StorageError.directoryCreationFailed(directoryURL.path)
            }
        }

        return directoryURL
    }

    // MARK: - File Operations

    /// Saves data to a file in the specified directory
    func save(
        _ data: Data,
        to directory: StorageDirectory,
        filename: String
    ) throws -> URL {
        let directoryURL = try url(for: directory)
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL, options: [.atomic])
            return fileURL
        } catch {
            throw StorageError.fileCopyFailed(error.localizedDescription)
        }
    }

    /// Copies a file from a source URL to the specified directory
    func copy(
        from sourceURL: URL,
        to directory: StorageDirectory,
        filename: String? = nil
    ) throws -> URL {
        let directoryURL = try url(for: directory)
        let destinationFilename = filename ?? sourceURL.lastPathComponent
        let destinationURL = directoryURL.appendingPathComponent(destinationFilename)

        // If source is already in destination directory, return as-is
        if sourceURL.deletingLastPathComponent() == directoryURL {
            return sourceURL
        }

        // Don't overwrite if file exists
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw StorageError.fileCopyFailed(error.localizedDescription)
        }
    }

    /// Generates a unique filename with UUID and extension
    func uniqueFilename(withExtension ext: String) -> String {
        let uuid = UUID().uuidString
        return ext.isEmpty ? uuid : "\(uuid).\(ext)"
    }

    /// Checks if a file exists at the given path
    func fileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    /// Deletes a file at the given URL
    func deleteFile(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }

    // MARK: - Migration

    /// Migrates existing files from old Documents directory to App Group container
    /// Call this once on first launch after adding App Group support
    func migrateExistingFiles() async throws {
        guard useAppGroup else {
            print("ℹ️ Skipping migration - App Group not configured")
            return
        }

        // Check if migration has already been performed
        let migrationKey = "has_migrated_to_app_group"
        if UserDefaults.standard.bool(forKey: migrationKey) {
            print("ℹ️ Files already migrated to App Group")
            return
        }

        print("🔄 Starting file migration to App Group container...")

        let oldDocumentsURL = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )

        // Migrate each directory
        try await migrateDirectory(
            from: oldDocumentsURL.appendingPathComponent("FolioMindAssets"),
            to: .assets
        )

        try await migrateDirectory(
            from: oldDocumentsURL.appendingPathComponent("FolioMindRecordings"),
            to: .recordings
        )

        // Mark migration as complete
        UserDefaults.standard.set(true, forKey: migrationKey)
        print("✅ Migration completed successfully")
    }

    private func migrateDirectory(
        from oldDirectory: URL,
        to newDirectory: StorageDirectory
    ) async throws {
        guard fileManager.fileExists(atPath: oldDirectory.path) else {
            print("ℹ️ No existing files in \(oldDirectory.lastPathComponent)")
            return
        }

        let newDirectoryURL = try url(for: newDirectory)
        let files = try fileManager.contentsOfDirectory(
            at: oldDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        print("📁 Migrating \(files.count) files from \(oldDirectory.lastPathComponent)...")

        for fileURL in files {
            let destinationURL = newDirectoryURL.appendingPathComponent(fileURL.lastPathComponent)

            if fileManager.fileExists(atPath: destinationURL.path) {
                continue // Skip if already exists
            }

            do {
                try fileManager.copyItem(at: fileURL, to: destinationURL)
            } catch {
                print("⚠️ Failed to migrate \(fileURL.lastPathComponent): \(error)")
                // Continue with other files instead of failing completely
            }
        }
    }
}
