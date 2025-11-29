# Privacy Setup Instructions

FolioMind requires several privacy permissions to function properly. Follow these steps to configure privacy descriptions in Xcode.

## Required Privacy Permissions

### 1. Photo Library Access
**Key:** `NSPhotoLibraryUsageDescription`
**Description:** "FolioMind needs access to your photo library to import and save document images."
**Why:** Used to import documents from Photos and save scanned documents

### 2. Camera Access
**Key:** `NSCameraUsageDescription`
**Description:** "FolioMind needs camera access to scan documents using the built-in document scanner."
**Why:** Required for VisionKit document scanning

### 3. Reminders Access
**Key:** `NSRemindersUsageDescription`
**Description:** "FolioMind needs access to Reminders to create and manage document-related reminders and follow-ups."
**Why:** Allows users to set reminders for document actions (payments, renewals, appointments)

### 4. Calendar Access
**Key:** `NSCalendarsUsageDescription`
**Description:** "FolioMind needs access to your calendar to create events for document-related appointments."
**Why:** Optional calendar event creation for insurance appointments, etc.

### 5. Photo Library Add Usage
**Key:** `NSPhotoLibraryAddUsageDescription`
**Description:** "FolioMind needs permission to save scanned documents to your photo library."
**Why:** Allows saving scanned documents back to Photos

## How to Add Privacy Descriptions in Xcode

### Method 1: Using Info Tab (Recommended)
1. Open the FolioMind project in Xcode
2. Select the **FolioMind** target
3. Go to the **Info** tab
4. Click the **+** button next to "Custom iOS Target Properties"
5. Add each privacy key from the list above
6. Set the value to the corresponding description

### Method 2: Using Build Settings
1. Open the FolioMind project in Xcode
2. Select the **FolioMind** target
3. Go to **Build Settings**
4. Search for "Info.plist"
5. Under "Packaging", find "Info.plist Values"
6. Add each privacy key with its description

### Method 3: Direct plist editing (if Info.plist exists)
If your project has an Info.plist file, you can add these keys directly:

\`\`\`xml
<key>NSPhotoLibraryUsageDescription</key>
<string>FolioMind needs access to your photo library to import and save document images.</string>
<key>NSCameraUsageDescription</key>
<string>FolioMind needs camera access to scan documents using the built-in document scanner.</string>
<key>NSRemindersUsageDescription</key>
<string>FolioMind needs access to Reminders to create and manage document-related reminders and follow-ups.</string>
<key>NSCalendarsUsageDescription</key>
<string>FolioMind needs access to your calendar to create events for document-related appointments.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>FolioMind needs permission to save scanned documents to your photo library.</string>
\`\`\`

## Privacy Manifest

The project includes a `PrivacyInfo.xcprivacy` file that declares:
- File timestamp access (for document metadata)
- UserDefaults access (for app preferences and API key storage)
- No data collection or tracking
- No third-party SDKs that track users

## Testing Privacy Permissions

To test that permissions work correctly:

1. **Photo Library:** Tap "Import" and select an image
2. **Camera/Scanner:** Tap "Scan" to launch document scanner (iOS 13+ only)
3. **Reminders:** Open a document, tap the "+" in Reminders section
4. **Calendar:** Create an appointment reminder from an insurance card

## Data Privacy & Security

FolioMind is designed with privacy in mind:
- ✅ **Local-first:** All documents and OCR processed on-device
- ✅ **No cloud storage:** Documents stay on your device
- ✅ **Secure credentials:** API keys encrypted in iOS Keychain
- ✅ **Optional LLM:** Apple Intelligence (on-device) or user-provided OpenAI key
- ✅ **No tracking:** No analytics or user tracking
- ✅ **No ads:** No advertising SDKs

## App Store Requirements

Before submitting to the App Store, ensure:
1. ✅ All privacy descriptions are added
2. ✅ PrivacyInfo.xcprivacy is included in the bundle
3. ✅ Privacy Policy URL is set (if applicable)
4. ✅ Data Use section filled out in App Store Connect
