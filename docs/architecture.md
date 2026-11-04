# Architecture

The ecosystem has two independent pieces: a copyable Obsidian starter vault and a native Mac tool. The vault is useful without the tool. Mahdi can connect to any vault that uses the documented daily layout.

Mahdi uses SwiftUI for the compact widget and note popover, AppKit for its floating panel and vault picker, and Foundation for local files. There are no remote services or third-party runtime packages.

`Sources/Mahdi/main.swift` holds the timer state, draft persistence, folder selection, and UI. `Sources/MahdiCore/DailyLog.swift` owns personal-date filenames, daily templates, insertion before the wrap-up section, and entry updates. The MahdiChecks executable runs core tests against temporary vaults only, with no XCTest dependency.

A lap moves through `ready → focus → closing → break → ready`. The deadline is an absolute date so a delayed timer tick does not stretch the countdown. Closing and starting the next lap require user action. Notes are saved after a short debounce and on app termination; drafts are also persisted separately.

Daily files contain no app metadata. The hidden index maps day/entry ID to its last plain line. If that exact line is still present, autosave replaces it. If someone changed it elsewhere, the app preserves that text and appends the new version. Files are written atomically, but the Markdown file and index are separate writes, not a multi-file transaction.

`scripts/build-mahdi.sh` creates an app bundle, installs its icon, and applies a local ad-hoc signature. The current bundle ID is retained for compatibility with the earliest local version. CI runs core tests and the same app packaging script on macOS.
