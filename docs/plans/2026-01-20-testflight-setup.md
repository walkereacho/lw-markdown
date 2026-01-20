# Atlantic.md TestFlight Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create an Xcode project wrapper to build and distribute the MarkdownEditor as "Atlantic.md" via TestFlight.

**Architecture:** Xcode project references existing SPM package as local dependency. All source code stays in Sources/MarkdownEditor. Xcode project only adds distribution config (Info.plist, entitlements, icon).

**Tech Stack:** Xcode 15+, XcodeGen (for project generation), Swift 5.9, macOS 13+

---

## Task 1: Install XcodeGen

XcodeGen generates Xcode projects from a simple YAML spec. Much cleaner than hand-writing .pbxproj files.

**Step 1: Check if XcodeGen is installed**

Run: `which xcodegen || echo "not installed"`

**Step 2: Install XcodeGen if needed**

Run: `brew install xcodegen`

**Step 3: Verify installation**

Run: `xcodegen --version`
Expected: Version number (e.g., "2.42.0")

---

## Task 2: Create Project Directory Structure

**Files:**
- Create: `Atlantic.md/` directory
- Create: `Atlantic.md/project.yml` (XcodeGen spec)

**Step 1: Create the project directory**

Run: `mkdir -p Atlantic.md`

**Step 2: Create XcodeGen project spec**

Create file `Atlantic.md/project.yml`:

```yaml
name: Atlantic.md
options:
  bundleIdPrefix: dev.eacho
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  generateEmptyDirectories: true

settings:
  base:
    PRODUCT_NAME: Atlantic.md
    MARKETING_VERSION: "1.0.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""  # Will be set in Xcode
    CODE_SIGN_STYLE: Automatic

packages:
  MarkdownEditor:
    path: ..

targets:
  Atlantic.md:
    type: application
    platform: macOS
    sources:
      - path: Sources
        type: group
    dependencies:
      - package: MarkdownEditor
        product: MarkdownEditor
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.eacho.markdown
        INFOPLIST_FILE: Info.plist
        CODE_SIGN_ENTITLEMENTS: Atlantic.md.entitlements
        ENABLE_HARDENED_RUNTIME: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: Info.plist
      properties:
        CFBundleName: Atlantic.md
        CFBundleDisplayName: Atlantic.md
        CFBundleIdentifier: $(PRODUCT_BUNDLE_IDENTIFIER)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundlePackageType: APPL
        CFBundleExecutable: $(EXECUTABLE_NAME)
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        NSPrincipalClass: NSApplication
        NSHighResolutionCapable: true
        CFBundleDocumentTypes:
          - CFBundleTypeName: Markdown Document
            CFBundleTypeRole: Editor
            LSHandlerRank: Default
            LSItemContentTypes:
              - net.daringfireball.markdown
              - public.plain-text
            CFBundleTypeExtensions:
              - md
              - markdown
        UTExportedTypeDeclarations: []
        UTImportedTypeDeclarations:
          - UTTypeIdentifier: net.daringfireball.markdown
            UTTypeDescription: Markdown Document
            UTTypeConformsTo:
              - public.plain-text
            UTTypeTagSpecification:
              public.filename-extension:
                - md
                - markdown
    entitlements:
      path: Atlantic.md.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.files.user-selected.read-write: true
```

**Step 3: Commit**

Run: `git add Atlantic.md/project.yml && git commit -m "feat: add XcodeGen project spec for Atlantic.md"`

---

## Task 3: Create Minimal Source Entry Point

The Xcode target needs its own entry point that calls into the SPM package.

**Files:**
- Create: `Atlantic.md/Sources/main.swift`

**Step 1: Create Sources directory**

Run: `mkdir -p Atlantic.md/Sources`

**Step 2: Create main.swift entry point**

Create file `Atlantic.md/Sources/main.swift`:

```swift
// Entry point for Atlantic.md (Xcode build)
// Delegates to the SPM package's main entry point

import AppKit

// The MarkdownEditor package uses @main on MarkdownEditorApp
// For the Xcode target, we need to start it manually
let app = NSApplication.shared
let delegate = NSApp.delegate  // Set by @NSApplicationMain or @main

// Run the application
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
```

**Step 3: Commit**

Run: `git add Atlantic.md/Sources/main.swift && git commit -m "feat: add Xcode entry point for Atlantic.md"`

---

## Task 4: Create Placeholder App Icon

**Files:**
- Create: `Atlantic.md/Assets.xcassets/AppIcon.appiconset/`

**Step 1: Create asset catalog structure**

Run: `mkdir -p "Atlantic.md/Assets.xcassets/AppIcon.appiconset"`

**Step 2: Create Contents.json for app icon**

Create file `Atlantic.md/Assets.xcassets/Contents.json`:

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 3: Create AppIcon Contents.json**

Create file `Atlantic.md/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "icon_16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_64.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Step 4: Generate placeholder icons using sips**

Run the following to create simple blue gradient placeholder icons:

```bash
# Create a 1024x1024 placeholder icon with ImageMagick or fall back to a solid color
if command -v convert &> /dev/null; then
  convert -size 1024x1024 gradient:'#1a5f7a-#57c5b6' \
    -gravity center -fill white -font Helvetica-Bold -pointsize 400 \
    -annotate 0 'A' \
    "Atlantic.md/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
else
  # Fallback: create icons with sips from a base image or use placeholder
  echo "ImageMagick not found. Creating solid color placeholder."
  # We'll create a simple Swift script to generate the icon
fi
```

If ImageMagick isn't available, create placeholder icons manually or use this Python script:

```bash
python3 << 'PYTHON'
from PIL import Image, ImageDraw, ImageFont
import os

sizes = [16, 32, 64, 128, 256, 512, 1024]
output_dir = "Atlantic.md/Assets.xcassets/AppIcon.appiconset"

for size in sizes:
    img = Image.new('RGB', (size, size), color='#1a5f7a')
    draw = ImageDraw.Draw(img)

    # Draw a simple "A" in the center
    font_size = int(size * 0.6)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
    except:
        font = ImageFont.load_default()

    text = "A"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    x = (size - text_width) / 2
    y = (size - text_height) / 2 - bbox[1]
    draw.text((x, y), text, fill='white', font=font)

    img.save(f"{output_dir}/icon_{size}.png")
    print(f"Created icon_{size}.png")
PYTHON
```

**Step 5: Commit**

Run: `git add Atlantic.md/Assets.xcassets && git commit -m "feat: add placeholder app icon for Atlantic.md"`

---

## Task 5: Generate Xcode Project

**Step 1: Run XcodeGen**

Run: `cd Atlantic.md && xcodegen generate`

Expected output:
```
⚙️  Generating plists...
⚙️  Generating project...
⚙️  Writing project...
Created project at Atlantic.md.xcodeproj
```

**Step 2: Verify project was created**

Run: `ls -la Atlantic.md/Atlantic.md.xcodeproj`

Expected: Directory exists with project.pbxproj inside

**Step 3: Add xcodeproj to gitignore (generated file)**

Add to `.gitignore`:
```
# Generated Xcode project (regenerate with: cd Atlantic.md && xcodegen)
Atlantic.md/Atlantic.md.xcodeproj
```

**Step 4: Commit gitignore update**

Run: `git add .gitignore && git commit -m "chore: ignore generated Xcode project"`

---

## Task 6: Fix Entry Point Integration

The SPM package uses `@main` attribute. We need to ensure the Xcode target properly links to it.

**Step 1: Check current entry point in SPM package**

Read: `Sources/MarkdownEditor/main.swift` or equivalent `@main` struct

**Step 2: Update project.yml if needed**

The Xcode target should NOT have its own main.swift if the SPM package already has one. Update `project.yml` to remove the Sources reference and just link the package:

Update `Atlantic.md/project.yml` targets section:

```yaml
targets:
  Atlantic.md:
    type: application
    platform: macOS
    dependencies:
      - package: MarkdownEditor
        product: MarkdownEditor
    settings:
      # ... rest of settings
```

Remove the `sources:` section entirely - the SPM package provides the executable.

**Step 3: Delete the separate main.swift**

Run: `rm -rf Atlantic.md/Sources`

**Step 4: Regenerate project**

Run: `cd Atlantic.md && xcodegen generate`

**Step 5: Commit**

Run: `git add Atlantic.md/project.yml && git commit -m "fix: use SPM package entry point directly"`

---

## Task 7: Test Local Build

**Step 1: Open project in Xcode**

Run: `open Atlantic.md/Atlantic.md.xcodeproj`

**Step 2: In Xcode, set your development team**

1. Select the project in the navigator
2. Select "Atlantic.md" target
3. Go to "Signing & Capabilities"
4. Select your team from the dropdown

**Step 3: Build the project**

Press Cmd+B or Product → Build

Expected: Build succeeds

**Step 4: Run the app**

Press Cmd+R or Product → Run

Expected: Atlantic.md launches

**Step 5: Test file opening**

In Terminal, with the app running:
```bash
# Create a test file
echo "# Test" > /tmp/test.md

# Open it with Atlantic.md
open -a "Atlantic.md" /tmp/test.md
```

Expected: The file opens in Atlantic.md

---

## Task 8: App Store Connect Setup (Manual)

This task requires manual steps in the browser.

**Step 1: Log in to App Store Connect**

Go to: https://appstoreconnect.apple.com

**Step 2: Create new app**

1. Click "Apps" → "+" → "New App"
2. Platform: macOS
3. Name: Atlantic.md
4. Primary language: English (U.S.)
5. Bundle ID: Select "dev.eacho.markdown" (register it first if needed)
6. SKU: atlantic-md-001 (or any unique identifier)

**Step 3: Register Bundle ID (if not already done)**

Go to: https://developer.apple.com/account/resources/identifiers/list

1. Click "+" to add new identifier
2. Select "App IDs" → Continue
3. Select "App" → Continue
4. Description: Atlantic.md
5. Bundle ID: Explicit → dev.eacho.markdown
6. Capabilities: Leave defaults (no extra capabilities needed)
7. Register

**Step 4: Return to App Store Connect and create the app**

---

## Task 9: Archive and Upload

**Step 1: In Xcode, select "Any Mac" as destination**

In the scheme/destination dropdown, select "Any Mac"

**Step 2: Create archive**

Product → Archive

Wait for archive to complete.

**Step 3: Distribute to TestFlight**

1. In the Organizer window (Window → Organizer), select the new archive
2. Click "Distribute App"
3. Select "TestFlight & App Store" → Next
4. Select "Upload" → Next
5. Keep default options → Next
6. Select your distribution certificate → Next
7. Upload

**Step 4: Wait for processing**

App Store Connect will process the build. You'll get an email when ready.

**Step 5: Add TestFlight testers**

In App Store Connect:
1. Go to your app → TestFlight tab
2. Add yourself as an internal tester
3. Once build is processed, enable it for testing

---

## Task 10: Verify TestFlight Install

**Step 1: Install from TestFlight**

Open TestFlight app on your Mac and install Atlantic.md

**Step 2: Test the app launches**

Launch Atlantic.md from Applications or Spotlight

**Step 3: Test file opening**

```bash
echo "# Hello from TestFlight" > /tmp/testflight-test.md
open -a "Atlantic.md" /tmp/testflight-test.md
```

Expected: File opens in the TestFlight-installed app

**Step 4: Celebrate!**

You've shipped your first TestFlight build!

---

## Troubleshooting

### XcodeGen fails with package resolution error
- Ensure `Package.swift` is in the parent directory
- Run `swift package resolve` in the root first

### Code signing errors
- Ensure you've selected your team in Xcode
- Check that bundle ID matches what's registered in Developer Portal

### App crashes on launch
- Check Console.app for crash logs
- Ensure `@main` entry point is correctly set up in SPM package

### "open -a" doesn't work after TestFlight install
- The app name in Terminal must match exactly: `open -a "Atlantic.md"`
- Check `/Applications` to verify the app installed correctly
