# App Group Setup Guide

## What Was Implemented

All file storage (photos, documents, audio recordings) now uses a shared App Group container:
- **App Group ID**: `group.com.lz.studio.FolioMind`
- **Storage Manager**: `FileStorageManager.swift`
- **Directories**:
  - `/FolioMindAssets/` - Photos and scanned documents
  - `/FolioMindRecordings/` - Audio recordings
  - `/Temp/` - Temporary files

## Files Modified

1. ✅ `FolioMind/Services/FileStorageManager.swift` - Created
2. ✅ `FolioMind/Services/AppServices.swift` - Updated to use shared container
3. ✅ `FolioMind/Views/DocumentScannerView.swift` - Updated to use shared container
4. ✅ `FolioMind/FolioMind.entitlements` - Created with App Group
5. ✅ `FolioMind.xcodeproj/project.pbxproj` - Added entitlements reference

## Apple Developer Portal Setup

### Required Steps (One-time)

1. **Go to Apple Developer Portal**
   - Visit: https://developer.apple.com/account/
   - Sign in with your Apple ID

2. **Navigate to Identifiers**
   - Certificates, Identifiers & Profiles → Identifiers
   - Find: **com.lz.studio.FolioMind**

3. **Enable App Groups**
   - Check the **App Groups** checkbox
   - Click **Edit** next to App Groups
   - Click **+** to add a new App Group

4. **Create App Group**
   - Identifier: `group.com.lz.studio.FolioMind`
   - Description: "FolioMind Shared Storage"
   - Click **Continue** → **Register**

5. **Assign to App**
   - Select the newly created App Group
   - Click **Save**

6. **Sync with Xcode**
   - Open **FolioMind.xcodeproj**
   - Select **FolioMind** target
   - Go to **Signing & Capabilities**
   - App Groups should be listed
   - Verify `group.com.lz.studio.FolioMind` is checked
   - If there's a warning, click **Refresh** or re-select your Team

## Verification

### Console Output (Success)
```
✅ Using App Group container: /path/to/shared/container
✅ Apple Intelligence available for intelligent field extraction
```

### Console Output (Not Configured Yet)
```
⚠️ App Group not available, using Documents directory: /path/to/documents
```

### Test File Storage
```swift
let storageManager = FileStorageManager.shared
let assetsURL = try storageManager.url(for: .assets)
print("Assets: \(assetsURL.path)")

let recordingsURL = try storageManager.url(for: .recordings)
print("Recordings: \(recordingsURL.path)")
```

## Migration

The app automatically migrates existing files on first launch:
- Copies files from old `Documents/FolioMindAssets/` → shared container
- Copies files from old `Documents/FolioMindRecordings/` → shared container
- Migration runs once (tracked via UserDefaults)
- Original files are preserved (non-destructive)

## Benefits

1. **Shared Access** - Files accessible across app extensions (widgets, shortcuts, etc.)
2. **iCloud Backup** - Shared container can sync via iCloud
3. **Better Organization** - Centralized file management
4. **Future-Proof** - Easy to add Siri shortcuts, widgets, etc.
5. **Data Persistence** - Survives app reinstalls when backed up

## Troubleshooting

### App Group not working after setup
- Clean build folder: Xcode → Product → Clean Build Folder
- Delete app from simulator/device and reinstall
- Verify Team ID matches in Signing & Capabilities

### Files not migrating
- Check console for migration errors
- Reset migration: `UserDefaults.standard.set(false, forKey: "has_migrated_to_app_group")`
- Reinstall the app

### Cannot create App Group in Developer Portal
- Ensure you have **Admin** or **App Manager** role in your team
- Verify your Apple Developer Program membership is active

## Future Extensions

With App Group configured, you can now add:
- **Widgets** - Display recent documents
- **Shortcuts** - Quick document capture
- **Share Extension** - Import from other apps
- **Today Extension** - Quick notes
- **WatchOS App** - View documents on Apple Watch

All these extensions will have access to the same shared files!
