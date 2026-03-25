# cmdx

**cmdx** is a lightweight macOS menu bar application that brings the missing **Cut (Cmd+X)** functionality to Finder. 

By default, macOS Finder only supports Copy (Cmd+C) and Move (Cmd+Option+V). `cmdx` runs quietly in the background, detects when you press `Cmd+X` in Finder, and allows you to paste the file seamlessly using `Cmd+V`.

## Features
- **Native-like Cut**: Enables standard Cmd+X inside Finder to cut files.
- **Menu Bar Integration**: Runs quietly in your menu bar with dynamic status indication.
- **Lightweight & Efficient**: Minimal resource footprint.
- **Privacy First**: Fully local and open source. (Requires Accessibility permissions to listen for the keyboard shortcut).

## Installation

You can easily download and install the app from here:

**[⬇️ Download cmdx.dmg](https://github.com/lukascakici/cmdx/raw/main/cmdx.installer.dmg)**

1. Download the `cmdx.installer.dmg` file from the link above.
2. Open the `.dmg` file and drag `cmdx.app` into your **Applications** folder.
3. Launch `cmdx` from your Applications.
4. When prompted, follow the instructions to grant **Accessibility** permissions (System Settings -> Privacy & Security -> Accessibility) so the app can detect your shortcuts.

## Requirements
- macOS 13.0 or later.
- Accessibility Permissions.

## Building from Source
1. Clone the repository.
2. Open `cmdx.xcodeproj` in Xcode.
3. Build and Run.

---
*Open Source Project*
