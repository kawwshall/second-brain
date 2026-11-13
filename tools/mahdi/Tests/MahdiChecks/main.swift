import Foundation
import MahdiCore

enum CheckFailure: Error { case failed(String) }
func expect(_ value: Bool, _ message: String = "check failed") throws {
    guard value else { throw CheckFailure.failed(message) }
}

struct DailyLogChecks {
    private func withVault(_ run: (DailyLog, Date) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Noon local time keeps expectations independent of the runner's time zone.
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!
        try run(DailyLog(vault: root), date)
    }
    func testCreatesPlainDailyEntryAndUpdatesWithoutDuplicates() throws {
        try withVault { log, date in
            try expect(log.dateName(date) == "26·308", "personal date")
            try log.write(id: "note", date: date, text: "first draft")
            try log.write(id: "note", date: date, text: "lecture 1\ncontinued!")
            let content = try String(contentsOf: log.file(date), encoding: .utf8)
            try expect(content.contains("12:00 lecture 1 continued!"))
            try expect(!content.contains("first draft"))
            try expect(!content.contains("<!--"))
            try expect(!content.contains("lap note"))
            try expect(content.components(separatedBy: "lecture 1").count == 2, "no duplicate autosaves")
            try expect(content.contains("redclub"))
            try expect(content.range(of: "lecture 1")!.lowerBound < content.range(of: "what got done")!.lowerBound)
        }
    }
    func testPreservesExistingTasksAndUnrelatedText() throws {
        try withVault { log, date in
            try FileManager.default.createDirectory(at: log.file(date).deletingLastPathComponent(), withIntermediateDirectories: true)
            let original = "# 26·308\n\nredclub\n- [ ] my existing task\n\nlogs\n9:00 my own entry\n\nwhat got done / where to start next\nmy summary\n"
            try original.write(to: log.file(date), atomically: true, encoding: .utf8)
            try log.write(id: "one", date: date, text: "new note")
            let content = try String(contentsOf: log.file(date), encoding: .utf8)
            try expect(content.contains("- [ ] my existing task"))
            try expect(content.contains("9:00 my own entry"))
            try expect(content.hasSuffix("my summary\n"))
        }
    }
    func testUserEditedEntryIsPreservedOnLaterAutosave() throws {
        try withVault { log, date in
            try log.write(id: "one", date: date, text: "original")
            let content = try String(contentsOf: log.file(date), encoding: .utf8)
            try content.replacingOccurrences(of: "12:00 original", with: "12:00 edited in Obsidian").write(to: log.file(date), atomically: true, encoding: .utf8)
            try log.write(id: "one", date: date, text: "continued in app")
            let updated = try String(contentsOf: log.file(date), encoding: .utf8)
            try expect(updated.contains("edited in Obsidian"))
            try expect(updated.contains("continued in app"))
        }
    }
    func testCorruptIndexDoesNotOverwriteDailyNote() throws {
        try withVault { log, date in
            try log.write(id: "one", date: date, text: "keep this")
            let original = try Data(contentsOf: log.file(date))
            try Data("invalid json".utf8).write(to: log.vault.appendingPathComponent(".laps-index.json"))
            var rejected = false
            do { try log.write(id: "one", date: date, text: "replacement") } catch { rejected = true }
            try expect(rejected, "corrupt index must reject save")
            try expect(try Data(contentsOf: log.file(date)) == original)
        }
    }
    func testLocalYearBoundaryAndLeapDay() throws {
        try withVault { log, _ in
            let cal = Calendar.current
            try expect(log.dateName(cal.date(from: DateComponents(year: 2028, month: 12, day: 31, hour: 12))!) == "28·366")
            try expect(log.dateName(cal.date(from: DateComponents(year: 2029, month: 1, day: 1, hour: 12))!) == "29·001")
        }
    }
}

let checks = DailyLogChecks()
try checks.testCreatesPlainDailyEntryAndUpdatesWithoutDuplicates()
try checks.testPreservesExistingTasksAndUnrelatedText()
try checks.testUserEditedEntryIsPreservedOnLaterAutosave()
try checks.testCorruptIndexDoesNotOverwriteDailyNote()
try checks.testLocalYearBoundaryAndLeapDay()
print("Passed 5 daily-log checks against temporary vaults.")

func checkDailyReport() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = DailyLog(vault: root)
    let calendar = Calendar.current
    let day = calendar.startOfDay(for: Date())
    func time(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }
    let original = """
    # test

    logs
    9:00 trying to fix keyboard
    9:01 fixed keyboard
    9:03 starting invoice matching
    9:04 idea about a timer
    9:15 submitted invoice matching
    9:20 back to invoice matching
    9:25 finished invoice matching

    what got done / where to start next
    - keep this manual bullet
    """
    let path = log.file(day)
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try original.write(to: path, atomically: true, encoding: .utf8)
    try log.saveTiming(id: "lap", timing: LapTiming(start: time(9, 3), end: time(9, 15)))
    try log.saveTiming(id: "break", timing: LapTiming(start: time(9, 15), end: time(9, 20), isBreak: true))
    try log.saveTiming(id: "overnight", timing: LapTiming(start: time(23, 50), end: time(23, 50).addingTimeInterval(25 * 60)))
    try log.writeReport(for: day, through: time(23, 59))
    try log.writeReport(for: day, through: time(23, 59))
    let contents = try String(contentsOf: path, encoding: .utf8)
    try expect(contents.contains("keyboard — ~1m from notes"), "completion closes estimated task")
    try expect(contents.contains("invoice matching — 12m timed + ~5m from notes"), "repeat groups without double counting")
    try expect(contents.contains("Unidentified focus — 9m timed"), "cutoff clips active lap")
    try expect(contents.contains("fixed keyboard · submitted invoice matching · finished invoice matching"), "completion outcomes")
    try expect(contents.contains("- keep this manual bullet"), "manual summary is preserved")
    try expect(contents.components(separatedBy: "### daily focus · Mahdi").count == 2, "report is replaced")
    try expect(!contents.contains("timer —"), "asides do not become activities")
    let next = calendar.date(byAdding: .day, value: 1, to: day)!
    try log.writeReport(for: day, through: next)
    let final = try String(contentsOf: path, encoding: .utf8)
    try expect(final.contains("Unidentified focus — 10m timed"), "midnight refresh completes prior day")
    try log.writeReport(for: next, through: next.addingTimeInterval(60 * 60))
    let nextNote = try String(contentsOf: log.file(next), encoding: .utf8)
    try expect(nextNote.contains("Unidentified focus — 15m timed"), "cross-midnight lap splits")
}

try checkDailyReport()
print("Passed daily-report checks against a temporary vault.")
