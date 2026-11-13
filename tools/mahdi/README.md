# Mahdi

A 240 × 70 point floating Pomodoro companion for macOS. Drag it wherever it is comfortable. It stays above ordinary windows and has a menu-bar timer too.

## Use

- Click the play button, connect your vault, and write an optional starting note. **Start lap** begins 25 minutes of focus.
- The note button opens a small editor. Notes autosave after an 800 ms typing pause. Continue editing the current entry, or choose **New note** for another one.
- At expiry, or when you choose **Finish…**, write an optional closing note. **Save & take 5** starts a five-minute break.
- When the break ends, the next lap waits for you to start it.

Daily entries contain only a local timestamp and the text you enter:

```text
12:00 starting lecture 1
12:14 check the worked example again
12:25 finished the example; start exercises next
```

No generated lap labels, task names, or comment markers are added. Multiline editor text becomes one log line. Blank notes add no entry. Existing clubs, tasks, and summaries stay in place. New pages follow the starter daily layout.

## Vault and local state

Choose a folder through the app; there is no machine-specific path in the source. Daily notes currently use the fixed folder `datodine` and `YY·DDD.md` names. Switch vaults when the timer is ready, after completing the lap and break.

| Location | Contents |
| --- | --- |
| `<vault>/datodine/YY·DDD.md` | Your plain Markdown daily log |
| `<vault>/.laps-index.json` | Entry IDs and the last saved line, used to update a note without duplicates |
| `~/Library/Application Support/SecondBrainPomodoro/config.json` | Your selected vault path |
| `~/Library/Application Support/SecondBrainPomodoro/session.json` | Timer deadline and note drafts |

The internal Application Support directory and bundle ID retain their original names so early Mahdi installations keep their sessions. Do not commit the index, config, or session files; they contain personal text or local paths. The app makes no network requests.

## Current limits

The timer uses wall-clock time. Sleep counts as elapsed time; expiry is detected when the Mac wakes. Sound requires the app to be running. Sessions and drafts survive relaunch. The floating position resets to the bottom right on launch.

Use one running copy of Mahdi per vault. Edits to the same log line in Obsidian cause the next app save to append a fresh line, preserving the external edit. Simultaneous writes from multiple devices/apps are not transactionally coordinated. A corrupt index produces a save error rather than silently replacing tracking data. Keep your normal vault backups.

This version has fixed 25/5 durations, no pause control, and no automatic next lap. It is a small working foundation for future updates.

## Build and check

From the repository root:

```sh
swift run --package-path tools/mahdi MahdiChecks
./scripts/build-mahdi.sh
```

The build script uses `swift`, `codesign`, and the included `.icns` asset. To package directly into a chosen directory, set `MAHDI_INSTALL_DIR`; quit an existing installed app before replacing it.

## Daily focus report

At 11:59 p.m. local time, Mahdi writes a short **daily focus · Mahdi** report under the day's wrap-up. It refreshes the report after midnight to include the last minute. If the Mac is asleep or the app is closed, missed reports are written when Mahdi runs again. The menu bar's **Write today’s focus report** command previews the day so far in the same section.

Keep writing your usual notes. The report reads timestamped lines under `logs`, recognizes common start, switch, and completion phrases, and groups similar activities. It uses recorded lap boundaries for timed focus and excludes recorded breaks. Time inferred between notes is marked with `~`. Ambiguous stretches between entries are unaccounted, and timed laps without a clear activity are shown as unidentified focus. Report inference is local and rule-based. Unusual wording can be missed, and a timer measures elapsed focus time even if you step away.

New timing data lives in the vault's private `.mahdi-timing.json`. Older notes can contribute estimates. Older laps have no recorded timing. Automatic reports begin with the day this version first runs for the connected vault.
