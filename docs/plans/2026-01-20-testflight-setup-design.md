# TestFlight Setup for Atlantic.md

## Overview

Convert the MarkdownEditor Swift Package Manager project into a distributable macOS app for TestFlight beta testing.

## App Identity

| Setting | Value |
|---------|-------|
| Bundle ID | `dev.eacho.markdown` |
| Display Name | Atlantic.md |
| Minimum macOS | 13.0 |
| Category | Developer Tools |
| Version | 1.0.0 (build 1) |

## Project Structure

```
Markdown/
├── Package.swift              (existing - unchanged)
├── Sources/                   (existing - unchanged)
├── Atlantic.md/               (NEW - Xcode project folder)
│   ├── Atlantic.md.xcodeproj
│   ├── Info.plist
│   ├── Atlantic.md.entitlements
│   └── Assets.xcassets/
│       └── AppIcon.appiconset/
```

The Xcode project references the existing SPM package as a local dependency. Existing `swift build` / `swift test` workflow remains unchanged.

## Entitlements

- `com.apple.security.app-sandbox`: true
- `com.apple.security.files.user-selected.read-write`: true

No iCloud, no network access, no other capabilities.

## Document Types

Register as handler for:
- `.md` files (UTI: `net.daringfireball.markdown`)
- `.markdown` files

This enables `open -a "Atlantic.md" file.md` and Finder "Open With" functionality.

## App Icon

Placeholder icon for initial TestFlight release. Can be updated later without changing bundle ID.

## Build & Upload Process

### One-time setup (App Store Connect)

1. Create new app record with bundle ID `dev.eacho.markdown`
2. App name: "Atlantic.md"
3. Add TestFlight testers

### Archive & Upload

```bash
# Via Xcode
Product → Archive → Distribute App → TestFlight & App Store

# Via CLI (optional)
xcodebuild archive -project Atlantic.md/Atlantic.md.xcodeproj -scheme Atlantic.md -archivePath build/Atlantic.md.xcarchive
xcodebuild -exportArchive -archivePath build/Atlantic.md.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/
```

## Verification

After TestFlight install, verify file opening works:
```bash
open -a "Atlantic.md" ~/path/to/file.md
```

## Future Enhancements (not in scope)

- iCloud document sync
- Custom app icon
- Auto-update mechanism
- Crash reporting
