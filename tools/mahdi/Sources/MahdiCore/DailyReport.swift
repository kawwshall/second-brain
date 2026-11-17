import Foundation

public struct LapTiming: Codable, Equatable {
    public let start: Date
    public let end: Date
    public let isBreak: Bool

    public init(start: Date, end: Date, isBreak: Bool = false) {
        self.start = start
        self.end = end
        self.isBreak = isBreak
    }
}

extension DailyLog {
    private var timingFile: URL { vault.appendingPathComponent(".mahdi-timing.json") }

    public func saveTiming(id: String, timing: LapTiming) throws {
        var timings = try readTimings()
        timings[id] = timing
        try JSONEncoder().encode(timings).write(to: timingFile, options: .atomic)
    }

    private func readTimings() throws -> [String: LapTiming] {
        guard FileManager.default.fileExists(atPath: timingFile.path) else { return [:] }
        return try JSONDecoder().decode([String: LapTiming].self, from: Data(contentsOf: timingFile))
    }

    public struct ReportSource: Equatable {
        fileprivate let notes: [ReportNote]
        fileprivate let timings: [LapTiming]
        fileprivate let start: Date
        fileprivate let end: Date

        public var modelInput: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            let entries = notes.map { "\(formatter.string(from: $0.time)) \($0.text)" }
            let intervals = timings.map {
                let from = formatter.string(from: max(start, $0.start))
                let clippedEnd = min(end, $0.end)
                let to = Calendar.current.isDate(clippedEnd, inSameDayAs: start)
                    ? formatter.string(from: clippedEnd) : "end of day"
                return "\($0.isBreak ? "Break" : "Timer") \(from)–\(to)"
            }
            return "Timestamped notes:\n" + entries.joined(separator: "\n") +
                "\nTimer intervals (clock time only):\n" + intervals.joined(separator: "\n")
        }

        fileprivate var timerTotal: String? {
            let points = Set(timings.flatMap { [max(start, $0.start), min(end, $0.end)] }).sorted()
            let duration = zip(points, points.dropFirst()).reduce(0.0) { sum, pair in
                let covering = timings.filter { $0.start <= pair.0 && $0.end >= pair.1 }
                if covering.isEmpty || covering.contains(where: { $0.isBreak }) { return sum }
                return sum + pair.1.timeIntervalSince(pair.0)
            }
            let seconds = Int(duration.rounded())
            guard seconds > 0 else { return nil }
            return "Mahdi timer total — \(seconds / 60)m \(seconds % 60)s"
        }
    }

    public func reportSource(for date: Date, through cutoff: Date) throws -> ReportSource? {
        let calendar = Calendar.current
        guard let day = calendar.dateInterval(of: .day, for: date) else { return nil }
        let end = min(day.end, cutoff)
        guard end > day.start else { return nil }
        let timings = try readTimings().values.filter { $0.start < end && $0.end > day.start && $0.end > $0.start }
        let path = file(date)
        let exists = FileManager.default.fileExists(atPath: path.path)
        guard exists || timings.contains(where: { !$0.isBreak }) else { return nil }
        let content = exists ? try String(contentsOf: path, encoding: .utf8) : template(date)
        var notes = ReportNote.read(from: content, day: day.start, before: end, calendar: calendar)
        if let overnight = timings.filter({ !$0.isBreak && $0.start < day.start }).map(\.start).min(),
           let previous = try? String(contentsOf: file(overnight), encoding: .utf8) {
            let prior = ReportNote.read(from: previous, day: calendar.startOfDay(for: overnight),
                                        before: day.start, calendar: calendar)
            notes = prior.filter { $0.time >= overnight.addingTimeInterval(-60) } + notes
        }
        guard !notes.isEmpty || timings.contains(where: { !$0.isBreak }) else { return nil }

        return ReportSource(notes: notes, timings: timings.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end < $1.end }
            return !$0.isBreak && $1.isBreak
        }, start: day.start, end: end)
    }

    @discardableResult
    public func writeReport(for date: Date, through cutoff: Date, summary: [String]? = nil,
                            source: ReportSource? = nil) throws -> Bool {
        guard let current = try reportSource(for: date, through: cutoff) else { return false }
        if let source, current != source { throw ReportError.notesChanged }
        let path = file(date)
        let content = FileManager.default.fileExists(atPath: path.path)
            ? try String(contentsOf: path, encoding: .utf8) : template(date)
        let lines: [String]
        if let summary {
            lines = summary.map { "- " + $0 } + (current.timerTotal.map { ["- " + $0] } ?? [])
        } else {
            lines = FocusReport(notes: current.notes, timings: current.timings,
                                start: current.start, end: current.end).lines
        }
        let block = (["%% mahdi-report %%"] + lines + ["%% /mahdi-report %%"]).joined(separator: "\n") + "\n"
        var updated = content
        if let existing = updated.range(of: #"(?m)^%% mahdi-report %%\n[\s\S]*?^%% /mahdi-report %%(?:\n|$)|^### daily focus · Mahdi[ \t]*\n(?:^> - [^\n]*\n?)*"#, options: .regularExpression) {
            updated.replaceSubrange(existing, with: block)
        } else if let wrap = updated.range(of: #"(?mi)^(?:#{1,6} +)?what got done / where to start next[ \t]*$"#, options: .regularExpression) {
            updated.insert(contentsOf: "\n\n" + block, at: wrap.upperBound)
        } else {
            updated += "\n\nwhat got done / where to start next\n\n" + block
        }
        if updated != content {
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try updated.write(to: path, atomically: true, encoding: .utf8)
        }
        return true
    }
}

private struct ReportNote: Equatable {
    let time: Date
    let text: String

    static func read(from content: String, day: Date, before end: Date, calendar: Calendar) -> [Self] {
        let timestamp = try! NSRegularExpression(pattern: #"^\s*(?:-\s+)?(\d{1,2}):(\d{2})\s*(am|pm)?\s+(.+)$"#, options: .caseInsensitive)
        var inLogs = false
        var notes: [Self] = []
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let heading = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).lowercased()
            if heading == "logs" { inLogs = true; continue }
            if heading.hasPrefix("what got done / where to start next") || trimmed.hasPrefix("#") {
                inLogs = false
            }
            guard inLogs, let match = timestamp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let h = Range(match.range(at: 1), in: line), var hour = Int(line[h]),
                  let m = Range(match.range(at: 2), in: line), let minute = Int(line[m]), minute < 60,
                  let body = Range(match.range(at: 4), in: line) else { continue }
            if let period = Range(match.range(at: 3), in: line) {
                guard (1...12).contains(hour) else { continue }
                hour = hour % 12 + (line[period].lowercased() == "pm" ? 12 : 0)
            }
            guard hour < 24,
                  let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day),
                  date < end else { continue }
            notes.append(Self(time: date, text: String(line[body])))
        }
        return notes.enumerated().sorted {
            $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
        }.map(\.element)
    }
}

private enum ReportError: LocalizedError {
    case notesChanged
    var errorDescription: String? { "Notes changed while the report was being drafted. Try again." }
}

private struct FocusReport {
    private struct Activity {
        let label: String
        let words: Set<String>
        var recorded: TimeInterval = 0
        var estimated: TimeInterval = 0
    }

    let lines: [String]

    init(notes: [ReportNote], timings: [LapTiming], start: Date, end: Date) {
        let starts = #"^(?:(?:now\s+)?(?:turning (?:heads|attention) to|switch(?:ing|ed)? to|back to|moving on to|(?:starting|started)(?: (?:work|working))?(?: (?:on|with))?|working on|resuming|resumed|continuing|trying to fix|fixing|studying|reviewing|building|debugging)\s+)"#
        let completions = #"^(?:i\s+)?(?:finished|completed|fixed|submitted|shipped|sent|solved|resolved|done with)\s+"#
        let pause = #"^(?:taking a break|break(?:$|\s)|lunch break|stopping(?:$|\s)|paused(?:$|\s)|done for (?:the day|today))"#
        let aside = #"^(?:i (?:am |was )?think(?:ing)?\b|idea\b|thought\b|btw\b|reminder\b)"#
        let stopWords: Set<String> = ["a", "an", "the", "to", "on", "it", "my", "with", "and", "for", "of", "this", "now", "again", "work", "working", "try", "trying", "just", "start", "starting", "finished", "completed", "fix", "fixed"]
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
                .subtracting(stopWords)
        }
        func clean(_ text: String) -> String {
            String(text.prefix(140)).replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        var activities: [Activity] = []
        func activity(_ label: String) -> Int {
            let keys = words(label)
            if let index = activities.firstIndex(where: {
                let shared = $0.words.intersection(keys).count
                return $0.label.caseInsensitiveCompare(label) == .orderedSame ||
                    (shared > 0 && Double(shared) / Double(max($0.words.count, keys.count)) >= 0.67)
            }) { return index }
            activities.append(Activity(label: clean(label), words: keys))
            return activities.count - 1
        }
        var changes: [(Date, Int?)] = []
        var estimates: [(DateInterval, Int)] = []
        var outcomes: [String] = []
        var active: (Date, Int)?

        func close(at time: Date) {
            if let (from, index) = active, time > from, time.timeIntervalSince(from) <= 90 * 60 {
                estimates.append((DateInterval(start: from, end: time), index))
            }
            active = nil
        }

        for note in notes {
            let lower = note.text.lowercased()
            if lower.range(of: aside, options: .regularExpression) != nil { continue }
            if lower.range(of: pause, options: .regularExpression) != nil {
                close(at: note.time)
                changes.append((note.time, nil))
                continue
            }
            if let match = note.text.range(of: completions, options: [.regularExpression, .caseInsensitive]) {
                let finished = words(String(note.text[match.upperBound...]))
                let related = active.map { !activities[$0.1].words.isDisjoint(with: finished) } ?? false
                if related {
                    close(at: note.time)
                    changes.append((note.time, nil))
                }
                if !outcomes.contains(note.text) { outcomes.append(note.text) }
                continue
            }
            let prefix = note.text.range(of: starts, options: [.regularExpression, .caseInsensitive])
            let troubleshooting = lower.range(of: " so (?:i(?: am)? )?trying to fix ", options: .regularExpression)
            let hasStartCue = prefix != nil || troubleshooting != nil
            guard hasStartCue else { continue }
            let label: String
            if let prefix { label = String(note.text[prefix.upperBound...]) }
            else if let troubleshooting { label = String(note.text[..<troubleshooting.lowerBound]) }
            else { continue }
            guard !words(label).isEmpty else { continue }
            let index = activity(label)
            if active?.1 != index {
                close(at: note.time)
                active = (note.time, index)
                changes.append((note.time, index))
            }
        }

        var boundaries = Set([start, end])
        for timing in timings {
            boundaries.insert(max(start, timing.start))
            boundaries.insert(min(end, timing.end))
        }
        for (interval, _) in estimates {
            boundaries.insert(max(start, interval.start))
            boundaries.insert(min(end, interval.end))
        }
        for (time, _) in changes { boundaries.insert(time) }
        let points = boundaries.sorted()
        var unnamed: TimeInterval = 0
        var unaccounted: TimeInterval = 0
        let firstEvidence = min(notes.first?.time ?? end, timings.map(\.start).min() ?? end)
        let lastEvidence = max(notes.last?.time ?? start, timings.map(\.end).max() ?? start)
        for (from, to) in zip(points, points.dropFirst()) where from >= start && to <= end {
            let seconds = to.timeIntervalSince(from)
            let covering = timings.filter { $0.start <= from && $0.end >= to }
            if covering.contains(where: { $0.isBreak }) { continue }
            if let lap = covering.first(where: { !$0.isBreak }) {
                if let change = changes.last(where: { $0.0 <= from && $0.0 >= lap.start.addingTimeInterval(-59.999) }),
                   let index = change.1 {
                    activities[index].recorded += seconds
                } else {
                    unnamed += seconds
                }
            } else if let estimate = estimates.first(where: { $0.0.start <= from && $0.0.end >= to }) {
                activities[estimate.1].estimated += seconds
            } else {
                unaccounted += max(0, min(to, lastEvidence).timeIntervalSince(max(from, firstEvidence)))
            }
        }

        func duration(_ seconds: TimeInterval, estimated: Bool = false) -> String {
            let wholeSeconds = max(1, Int(seconds.rounded()))
            let minutes = wholeSeconds / 60
            if estimated {
                if minutes == 0 { return "<1m" }
                if minutes < 60 { return "~\(minutes)m" }
                return "~\(minutes / 60)h \(minutes % 60)m"
            }
            var parts: [String] = []
            if minutes >= 60 { parts.append("\(minutes / 60)h") }
            if minutes % 60 > 0 { parts.append("\(minutes % 60)m") }
            if wholeSeconds % 60 > 0 { parts.append("\(wholeSeconds % 60)s") }
            return parts.joined(separator: " ")
        }
        let ranked = activities.filter { $0.recorded + $0.estimated > 0 }.sorted {
            let lhs = $0.recorded + $0.estimated, rhs = $1.recorded + $1.estimated
            return lhs == rhs ? $0.label < $1.label : lhs > rhs
        }
        var result = ranked.map { activity in
            var parts: [String] = []
            if activity.recorded > 0 { parts.append(duration(activity.recorded) + " timed") }
            if activity.estimated > 0 { parts.append(duration(activity.estimated, estimated: true) + " from notes") }
            return "- " + activity.label + " — " + parts.joined(separator: " + ")
        }
        if unnamed > 0 { result.append("- Unidentified focus — " + duration(unnamed) + " timed") }
        if unaccounted > 0 { result.append("- Unaccounted between entries — " + duration(unaccounted, estimated: true)) }
        if !outcomes.isEmpty { result.append("- Recorded outcomes — " + outcomes.map(clean).joined(separator: " · ")) }
        if result.isEmpty { result.append("- No activity duration could be inferred from the available entries.") }
        lines = result
    }
}
