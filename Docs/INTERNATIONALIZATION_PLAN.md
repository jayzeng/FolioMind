# FolioMind Internationalization (i18n) Plan
## Adding Simplified Chinese Support

**Status**: Planning Phase
**Target Languages**: Simplified Chinese (zh-Hans) initially, with architecture for future expansion
**Last Updated**: 2025-11-29

---

## Executive Summary

This document outlines the complete strategy for adding internationalization to FolioMind, starting with simplified Chinese (zh-Hans). The app currently has zero localization infrastructure and ~500+ hardcoded English strings across UI, alerts, errors, and system permissions.

**Estimated Effort**: 20-30 hours total
- Implementation: 12-16 hours
- Translation: 4-6 hours
- Testing: 4-8 hours

---

## Current State Analysis

### Project Configuration
- **Platform**: iOS 18.4+
- **Build System**: Xcode 16.3
- **UI Framework**: SwiftUI + SwiftData
- **Current Languages**: English only (`en`, `Base`)
- **String Catalog Preference**: ✅ Already enabled (`LOCALIZATION_PREFERS_STRING_CATALOGS = YES`)
- **Existing Localization**: ❌ None (no .strings, .xcstrings, or .lproj files)
- **Current String Usage**: ❌ All hardcoded, no `NSLocalizedString` or `String(localized:)` usage

### String Inventory

| Category | Count | Files | Complexity |
|----------|-------|-------|------------|
| UI Labels & Buttons | ~150 | All views | Low |
| Document Type Names | 7 | DomainModels.swift, ContentView.swift | Medium |
| Field Labels | ~30 | DocumentDetailPageView.swift | Medium |
| Status Messages | ~40 | ContentView.swift, DocumentDetailPageView.swift | Medium |
| Error Messages | ~20 | All views | High |
| Empty States | ~15 | ContentView.swift, DocumentDetailPageView.swift | Medium |
| Alerts & Confirmations | ~25 | All views | High |
| Settings & Privacy | ~20 | SettingsView.swift, Info.plist | High |
| Permission Descriptions | 5 | Info.plist (via project.pbxproj) | High |
| **Total** | **~310+** | **8+ files** | **Mixed** |

**Note**: This doesn't include string interpolations and dynamic content which adds significant complexity.

---

## Recommended Architecture

### 1. String Catalog Strategy ✅ RECOMMENDED

**Use Xcode String Catalogs (.xcstrings)** - Apple's modern localization format introduced in Xcode 15.

#### Why String Catalogs?
- ✅ Already configured in project (`LOCALIZATION_PREFERS_STRING_CATALOGS = YES`)
- ✅ Modern, JSON-based, version-control friendly
- ✅ Built-in plural support (though Chinese doesn't need traditional plurals)
- ✅ Automatic extraction from code
- ✅ Context preservation and translation comments
- ✅ Xcode native UI for translators
- ✅ Better merge conflict handling than .strings files
- ✅ Supports device-specific and region-specific variants

#### Organization Strategy

**Option A: Single Catalog (Recommended for Phase 1)**
```
FolioMind/Resources/
└── Localizable.xcstrings
```
- **Pros**: Simple, single source of truth, easier to maintain initially
- **Cons**: Can become large (but searchable in Xcode)

**Option B: Feature-Based Catalogs (Future)**
```
FolioMind/Resources/
├── Localizable.xcstrings        # Core app strings
├── Settings.xcstrings           # Settings view
├── DocumentDetail.xcstrings     # Document detail view
└── Errors.xcstrings             # Error messages
```
- **Pros**: Better organization, parallel translation work, smaller files
- **Cons**: More complex, need to specify table name in code

**Decision**: Start with Option A, migrate to Option B if needed after 5+ languages.

---

### 2. Code Changes Required

#### Phase 1: Core Infrastructure (4-6 hours)

**A. Create String Catalog**
1. In Xcode: File → New → Resource → Strings Catalog
2. Name: `Localizable.xcstrings`
3. Add to `FolioMind` target
4. Location: `FolioMind/Resources/` (create folder)

**B. Add Simplified Chinese Language**
1. Project Settings → FolioMind target → Info tab
2. Localizations section → Click `+`
3. Select "Chinese, Simplified (zh-Hans)"
4. Check `Localizable.xcstrings` in dialog

**C. Update project.pbxproj**
```
knownRegions = (
    en,
    Base,
    "zh-Hans",  // ADD THIS
);
```

#### Phase 2: Code Migration (12-16 hours)

**Strategy**: Use SwiftUI's `String(localized:)` initializer (iOS 15.0+)

**Migration Pattern**:
```swift
// BEFORE
Text("Settings")
.navigationTitle("FolioMind")
Button("Delete") { ... }

// AFTER
Text(String(localized: "settings.title"))
.navigationTitle(String(localized: "app.name"))
Button(String(localized: "action.delete")) { ... }
```

**Recommended String Key Naming Convention**:
```swift
// Pattern: <feature>.<component>.<purpose>
"app.name"                          // FolioMind
"settings.title"                    // Settings
"settings.intelligence.section"     // Intelligence
"action.delete"                     // Delete
"action.edit"                       // Edit
"action.save"                       // Save
"document.type.creditCard"          // Credit Card
"document.field.cardholder"         // Cardholder
"alert.delete.title"                // Delete Document
"alert.delete.message"              // Are you sure...
"error.scanning.unavailable"        // Document scanning is unavailable
"status.searching"                  // Searching…
"empty.noDocuments.title"           // No Documents
"empty.noDocuments.message"         // Import or scan documents...
```

**Benefits of this convention**:
- Clear hierarchy and grouping
- Easy searching in Xcode
- Prevents key collisions
- Self-documenting

---

### 3. Special Considerations for Chinese

#### A. Text Direction
- **Chinese**: Left-to-Right (LTR) ✅ Same as English
- **Action**: No special RTL handling needed
- **Future**: If adding Arabic/Hebrew, SwiftUI automatically handles RTL

#### B. Font Support
- **System Fonts**: Already support Chinese ✅
- **Custom Fonts**: If added later, ensure CJK (Chinese-Japanese-Korean) character support
- **Weight**: Chinese characters often look better with slightly lighter font weights

#### C. Text Expansion
- **Chinese → English**: Chinese is often **30-50% shorter** than English
- **Impact**: More white space in Chinese UI (positive)
- **Action**: Test layouts but likely no changes needed due to compression

#### D. Number & Date Formatting
```swift
// CURRENT (Good! Already using system formatters)
document.createdAt.formatted(date: .abbreviated, time: .shortened)

// Will automatically show:
// English: "Nov 29, 2025, 2:30 PM"
// Chinese: "2025年11月29日 下午2:30"
```
✅ **No changes needed** - already using system formatters

#### E. Plural Forms
Chinese doesn't have traditional plural forms like English:
- English: "1 document" vs "2 documents"
- Chinese: "1 个文档" vs "2 个文档" (same word)

**Current Code**:
```swift
Text("\(audioNotes.count) saved")  // ❌ Missing plural handling
Text("\(item.documentCount) document\(item.documentCount == 1 ? "" : "s")")  // ❌ English-specific
```

**After Localization**:
```swift
Text("\(audioNotes.count) " + String(localized: "audio.count.saved",
     defaultValue: "saved"))

// In Localizable.xcstrings:
// English: "saved" (no plural needed in context)
// Chinese: "已保存"
```

For explicit counts with measure words:
```swift
// Use stringsdict or String Catalog plural variations
String(localized: "document.count", defaultValue: "^[\(count) document](inflect: true)")

// Localizable.xcstrings handles:
// en: "one": "%lld document", "other": "%lld documents"
// zh-Hans: "other": "%lld 个文档" (Chinese uses same form)
```

---

### 4. Permission Strings (Info.plist)

**Current Location**: Embedded in `project.pbxproj` as INFOPLIST_KEY_*

**Migration Strategy**:

**Option A: Create InfoPlist.strings** (Traditional)
```
FolioMind/Resources/
├── en.lproj/
│   └── InfoPlist.strings
└── zh-Hans.lproj/
    └── InfoPlist.strings
```

**Option B: Move to dedicated Info.plist** (Better)
1. Create `FolioMind/Info.plist`
2. Move all `INFOPLIST_KEY_*` from project.pbxproj to Info.plist
3. Localize Info.plist file

**Strings to Localize**:
```
NSCalendarsUsageDescription
NSCameraUsageDescription
NSMicrophoneUsageDescription
NSPhotoLibraryUsageDescription
NSRemindersUsageDescription
```

**Recommended**: Use Option B for cleaner project structure.

---

### 5. Dynamic Content Localization

#### A. Document Type Enum

**Current**:
```swift
extension DocumentType {
    var displayName: String {
        switch self {
        case .creditCard: "Credit Card"
        case .insuranceCard: "Insurance"
        // ...
        }
    }
}
```

**After**:
```swift
extension DocumentType {
    var displayName: String {
        switch self {
        case .creditCard:
            String(localized: "document.type.creditCard", defaultValue: "Credit Card")
        case .insuranceCard:
            String(localized: "document.type.insuranceCard", defaultValue: "Insurance Card")
        case .idCard:
            String(localized: "document.type.idCard", defaultValue: "ID Card")
        case .letter:
            String(localized: "document.type.letter", defaultValue: "Letter")
        case .billStatement:
            String(localized: "document.type.billStatement", defaultValue: "Bill Statement")
        case .receipt:
            String(localized: "document.type.receipt", defaultValue: "Receipt")
        case .generic:
            String(localized: "document.type.generic", defaultValue: "Document")
        }
    }
}
```

#### B. Reminder Types
```swift
enum ReminderType: String, Codable, CaseIterable {
    case call, appointment, payment, renewal, followUp, custom

    var displayName: String {
        switch self {
        case .call: String(localized: "reminder.type.call", defaultValue: "Call")
        case .appointment: String(localized: "reminder.type.appointment", defaultValue: "Appointment")
        case .payment: String(localized: "reminder.type.payment", defaultValue: "Payment")
        case .renewal: String(localized: "reminder.type.renewal", defaultValue: "Renewal")
        case .followUp: String(localized: "reminder.type.followUp", defaultValue: "Follow Up")
        case .custom: String(localized: "reminder.type.custom", defaultValue: "Custom")
        }
    }
}
```

#### C. Field Source Enum
```swift
enum FieldSource: String, Codable {
    case vision, gemini, openai, fused

    var displayName: String {
        switch self {
        case .vision: String(localized: "field.source.vision", defaultValue: "Vision")
        case .gemini: String(localized: "field.source.gemini", defaultValue: "Gemini")
        case .openai: String(localized: "field.source.openai", defaultValue: "OpenAI")
        case .fused: String(localized: "field.source.fused", defaultValue: "Fused")
        }
    }
}
```

#### D. Extracted Field Names

**Challenge**: Fields are extracted dynamically from documents (e.g., "cardholder", "member_id", "expiry_date")

**Strategy**: Create a mapping for common field names, fallback to capitalized English

```swift
extension Field {
    var localizedKey: String {
        // Map common field keys to localized strings
        let commonFields: [String: String] = [
            "cardholder": "field.name.cardholder",
            "member_id": "field.name.memberId",
            "group_number": "field.name.groupNumber",
            "expiry_date": "field.name.expiryDate",
            "card_number": "field.name.cardNumber",
            // ... add more as needed
        ]

        if let localizedKey = commonFields[key.lowercased()] {
            return String(localized: String.LocalizationValue(stringLiteral: localizedKey),
                          defaultValue: String.LocalizationValue(stringLiteral: key.capitalized))
        }

        // Fallback: just capitalize
        return key.capitalized.replacingOccurrences(of: "_", with: " ")
    }
}
```

---

### 6. String Interpolation Patterns

**Current Pattern**:
```swift
Text("Are you sure you want to delete \"\(document.title)\"?")
Text("No results for \"\(searchText)\"")
Text("\(item.documentCount) document\(item.documentCount == 1 ? "" : "s")")
```

**Chinese Considerations**:
- Chinese uses different quotation marks: 「」or ""
- Word order may differ
- Need flexible interpolation

**Best Practice**:
```swift
// Use String interpolation in localized strings
String(localized: "alert.delete.message \(document.title)")

// In Localizable.xcstrings:
// en: "Are you sure you want to delete \"%@\"? This action cannot be undone."
// zh-Hans: "您确定要删除「%@」吗？此操作无法撤销。"

// With String Catalog:
String(localized: "alert.delete.message",
       defaultValue: "Are you sure you want to delete \"\(document.title)\"?",
       comment: "Confirmation message when deleting a document")
```

**Complex Example**:
```swift
// BEFORE
private var searchEmptyTitle: String {
    if let selectedSpotlightName {
        return "No results for \"\(searchText)\" with \(selectedSpotlightName)"
    }
    return "No results for \"\(searchText)\""
}

// AFTER
private var searchEmptyTitle: String {
    if let selectedSpotlightName {
        return String(localized: "search.empty.withFilter \(searchText) \(selectedSpotlightName)",
                      defaultValue: "No results for \"\(searchText)\" with \(selectedSpotlightName)",
                      comment: "Empty search results with filter applied")
    }
    return String(localized: "search.empty.noFilter \(searchText)",
                  defaultValue: "No results for \"\(searchText)\"",
                  comment: "Empty search results without filter")
}
```

---

### 7. Testing Strategy

#### A. Visual Testing
1. **Language Switching**: Settings app → General → Language & Region → iPhone Language
2. **Key Screens to Test**:
   - Main document grid (ContentView)
   - Document detail with all tabs
   - Settings screen
   - All alert dialogs
   - Empty states
   - Status banners

#### B. Layout Testing
- ✅ Text truncation (unlikely in Chinese due to compression)
- ✅ Button widths
- ✅ Navigation titles
- ✅ Multi-line labels

#### C. Functional Testing
```swift
// Unit test example for localized strings
func testDocumentTypeLocalization() {
    // Test that all document types have localizations
    for docType in DocumentType.allCases {
        let displayName = docType.displayName
        XCTAssertFalse(displayName.isEmpty)
        // Could add language-specific assertions
    }
}
```

#### D. Screenshot Testing
- Use Xcode's screenshot testing for both languages
- Compare layouts side-by-side

---

### 8. Translation Workflow

#### Phase 1: Extract All Strings
```bash
# After implementing String(localized:) everywhere
# Xcode will automatically populate Localizable.xcstrings with:
# - Key
# - Default Value (English)
# - Comment (from code)
```

#### Phase 2: Translation
1. **Open `Localizable.xcstrings` in Xcode**
2. **Select "zh-Hans" column**
3. **Translate each string**

**Translation Best Practices**:
- Keep technical terms in English when common (e.g., "OCR")
- Use appropriate measure words (个, 张, 条)
- Match tone: FolioMind seems professional/utility → use standard Mandarin
- Consistency: Create a glossary for key terms

**Key Terms Glossary**:
| English | Simplified Chinese | Notes |
|---------|-------------------|-------|
| Document | 文档 | Standard translation |
| Scan | 扫描 | Verb and noun |
| Import | 导入 | Standard for file operations |
| Extract | 提取 | For data extraction |
| Field | 字段 | Database/form field |
| OCR | OCR | Keep as-is, widely understood |
| Credit Card | 信用卡 | Standard |
| Insurance | 保险 | Standard |
| Reminder | 提醒 | Standard |
| Settings | 设置 | Standard |
| Delete | 删除 | Standard action |
| Cancel | 取消 | Standard action |
| Save | 保存 | Standard action |

#### Phase 3: Professional Review (Recommended)
- Native speaker review
- Context testing (not just string by string)
- Consistency check across all strings

---

### 9. Future Expansion Readiness

This architecture supports easy addition of:
- Traditional Chinese (zh-Hant) - Minimal effort, mostly same translations
- Japanese (ja) - Requires new translations
- Korean (ko) - Requires new translations
- Spanish (es) - Requires new translations + text expansion consideration
- French (fr) - Requires text expansion consideration (~20% longer)
- German (de) - Requires text expansion consideration (~30% longer)
- Arabic (ar) - Requires RTL layout testing
- Hebrew (he) - Requires RTL layout testing

**To add a new language**:
1. Project Settings → Info → Localizations → `+`
2. Select language
3. Export XLIFF for translation (File → Export Localizations)
4. Import translated XLIFF
5. Test

---

## Implementation Checklist

### Pre-Implementation
- [ ] Create `FolioMind/Resources/` directory
- [ ] Review all hardcoded strings across codebase
- [ ] Set up translation glossary
- [ ] Decide on string key naming convention (use recommended above)

### Phase 1: Infrastructure (Day 1-2)
- [ ] Create `Localizable.xcstrings` file
- [ ] Add zh-Hans localization to project
- [ ] Update `project.pbxproj` knownRegions
- [ ] Create `displayName` extensions for all enums
- [ ] Set up InfoPlist.strings or Info.plist

### Phase 2: Code Migration (Day 3-7)
- [ ] Migrate ContentView.swift (~150 strings)
- [ ] Migrate SettingsView.swift (~20 strings)
- [ ] Migrate DocumentDetailPageView.swift (~100 strings)
- [ ] Migrate DocumentEditView.swift (~15 strings)
- [ ] Migrate remaining views
- [ ] Migrate all Alert strings
- [ ] Migrate all error messages
- [ ] Migrate permission descriptions
- [ ] Handle string interpolations
- [ ] Handle plural forms

### Phase 3: Translation (Day 8-10)
- [ ] Translate all UI strings to Simplified Chinese
- [ ] Translate permission descriptions
- [ ] Translate error messages
- [ ] Translate alert messages
- [ ] Review for consistency
- [ ] Professional review (if available)

### Phase 4: Testing (Day 11-12)
- [ ] Switch device to Chinese
- [ ] Test all main flows
- [ ] Test all empty states
- [ ] Test all error states
- [ ] Test all alerts/confirmations
- [ ] Screenshot comparison
- [ ] Layout validation
- [ ] Fix any issues found

### Phase 5: Documentation
- [ ] Update README with localization info
- [ ] Document translation workflow
- [ ] Create contributor guide for new languages
- [ ] Update app description for China App Store (if applicable)

---

## Risks & Mitigations

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Strings missed during migration | Medium | Medium | Use `grep` to find all hardcoded strings before starting |
| Incorrect Chinese translations | High | Medium | Native speaker review before release |
| Layout breaks with Chinese text | Low | Low | Chinese is shorter; test anyway |
| Xcode String Catalog bugs | Medium | Low | Have .strings fallback plan |
| OCR accuracy in Chinese documents | High | High | Separate issue; document in app |
| Dynamic field names not translated | Medium | High | Implement fallback mapping (see Section 5D) |

---

## Alternative Approaches Considered

### ❌ Traditional .strings Files
- **Why Not**: Legacy format, harder to merge, no automatic plural support
- **When to Use**: If supporting Xcode < 15 (not applicable)

### ❌ Third-Party i18n Libraries (SwiftGen, R.swift)
- **Why Not**: Adds dependency, String Catalogs are now native and better
- **When to Use**: If need type-safe keys (can reconsider later)

### ❌ Server-Side Strings
- **Why Not**: Requires backend, complicates offline usage
- **When to Use**: For dynamic content that changes frequently (not applicable)

---

## Cost-Benefit Analysis

### Costs
- **Development Time**: 20-30 hours (initial implementation)
- **Translation Cost**: $0 if self-translated, ~$500-800 for professional (310 strings × $1.50-2.50/string)
- **Maintenance**: ~1-2 hours per major feature addition (ongoing)
- **Testing Time**: ~8 hours per language added

### Benefits
- **Market Expansion**: Access to 1.4B Chinese speakers
- **User Experience**: Native language support increases engagement
- **App Store**: Required for China App Store distribution
- **Professionalism**: Shows attention to detail and global mindset
- **Future-Ready**: Architecture supports rapid expansion to other languages
- **Accessibility**: Better UX for non-English speakers

### ROI
- If targeting Chinese market: **High ROI**
- If just preparing for future: **Medium ROI**
- If not targeting international users: **Low ROI**

---

## Recommended Timeline

### Conservative Estimate (Part-Time, 2-3 weeks)
- **Week 1**: Infrastructure + ContentView migration (8-10 hours)
- **Week 2**: Remaining views migration + testing (8-10 hours)
- **Week 3**: Translation + final testing (8-10 hours)

### Aggressive Estimate (Full-Time, 1 week)
- **Day 1-2**: Infrastructure + 50% code migration
- **Day 3-4**: Complete code migration + testing
- **Day 5**: Translation + final QA

---

## Success Criteria

### Must Have
- ✅ All user-visible strings localized
- ✅ App launches in Chinese when device language is zh-Hans
- ✅ No English strings visible in Chinese mode
- ✅ All permission dialogs in Chinese
- ✅ Date/time formatted correctly in Chinese

### Should Have
- ✅ Professional Chinese translation review
- ✅ All layouts tested and working
- ✅ Screenshot tests for both languages
- ✅ Documentation for future translators

### Nice to Have
- ⭐ Simplified + Traditional Chinese
- ⭐ Third language (Japanese/Korean)
- ⭐ Automated CI checks for missing translations
- ⭐ In-app language switcher (Settings screen)

---

## Next Steps

1. **Get Stakeholder Approval**: Review this plan with team/stakeholders
2. **Decide on Timeline**: Conservative vs Aggressive approach
3. **Assign Resources**: Who will do development vs translation?
4. **Set Up Project**: Create branches, milestones, tasks
5. **Begin Implementation**: Follow checklist above

---

## Questions for Discussion

1. **Translation**: Self-translate or hire professional translator?
2. **Scope**: Simplified Chinese only, or also Traditional Chinese?
3. **Timeline**: How urgent is Chinese support?
4. **Testing**: Who will test Chinese UI thoroughly?
5. **Maintenance**: Who maintains translations when adding features?
6. **Future**: Which languages after Chinese?
7. **China App Store**: Planning to submit to China App Store? (Different requirements)

---

## Appendix A: Code Examples

### Example 1: Simple Text Localization
```swift
// BEFORE
Text("Settings")

// AFTER
Text(String(localized: "settings.title", defaultValue: "Settings",
            comment: "Settings screen title"))

// Or shorter if default value matches key:
Text(String(localized: "Settings"))
```

### Example 2: Button with Action
```swift
// BEFORE
Button("Delete") { deleteDocument() }

// AFTER
Button(String(localized: "action.delete", defaultValue: "Delete",
              comment: "Delete button label")) {
    deleteDocument()
}
```

### Example 3: Alert with Interpolation
```swift
// BEFORE
.alert("Delete Document", isPresented: $showDeleteAlert) {
    Button("Cancel", role: .cancel) { }
    Button("Delete", role: .destructive) { deleteDocument() }
} message: {
    Text("Are you sure you want to delete \"\(document.title)\"? This action cannot be undone.")
}

// AFTER
.alert(String(localized: "alert.delete.title", defaultValue: "Delete Document"),
       isPresented: $showDeleteAlert) {
    Button(String(localized: "action.cancel", defaultValue: "Cancel"),
           role: .cancel) { }
    Button(String(localized: "action.delete", defaultValue: "Delete"),
           role: .destructive) { deleteDocument() }
} message: {
    Text(String(localized: "alert.delete.message \(document.title)",
                defaultValue: "Are you sure you want to delete \"\(document.title)\"? This action cannot be undone.",
                comment: "Delete confirmation message with document title"))
}
```

### Example 4: Navigation Title
```swift
// BEFORE
.navigationTitle("FolioMind")

// AFTER
.navigationTitle(String(localized: "app.name", defaultValue: "FolioMind",
                        comment: "App name, shown in navigation bar"))
```

### Example 5: Enum Extension
```swift
// BEFORE
extension DocumentType {
    var displayName: String {
        switch self {
        case .creditCard: "Credit Card"
        case .insuranceCard: "Insurance"
        // ...
        }
    }
}

// AFTER
extension DocumentType {
    var displayName: String {
        let key = "document.type.\(self.rawValue)"
        switch self {
        case .creditCard:
            return String(localized: String.LocalizationValue(stringLiteral: key),
                          defaultValue: "Credit Card",
                          comment: "Document type: Credit Card")
        case .insuranceCard:
            return String(localized: String.LocalizationValue(stringLiteral: key),
                          defaultValue: "Insurance Card",
                          comment: "Document type: Insurance Card")
        // ... continue for all cases
        }
    }
}
```

---

## Appendix B: String Catalog Structure

Example `Localizable.xcstrings` structure:
```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "app.name" : {
      "comment" : "App name",
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "FolioMind"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "FolioMind"
          }
        }
      }
    },
    "action.delete" : {
      "comment" : "Delete button label",
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Delete"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "删除"
          }
        }
      }
    }
  },
  "version" : "1.0"
}
```

---

## Appendix C: Useful Commands

### Find all hardcoded strings
```bash
# Find Text("...") patterns
grep -r 'Text("' FolioMind/ --include="*.swift"

# Find Button("...") patterns
grep -r 'Button("' FolioMind/ --include="*.swift"

# Find .navigationTitle("...") patterns
grep -r '.navigationTitle("' FolioMind/ --include="*.swift"

# Find all string literals (broad search)
grep -r '"[^"]*"' FolioMind/ --include="*.swift" | grep -v "//"
```

### Export for translation
```bash
# In Xcode: Product → Export Localizations...
# Generates XLIFF files for translators
```

### Validate String Catalog
```bash
# Xcode automatically validates, but you can also:
plutil -lint FolioMind/Resources/Localizable.xcstrings
```

---

**End of Plan Document**
