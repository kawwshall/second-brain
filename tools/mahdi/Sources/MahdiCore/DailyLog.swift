import Foundation

public struct DailyLog {
    public let vault: URL
    public init(vault: URL) { self.vault = vault }
    public func dateName(_ date: Date) -> String {
        let cal = Calendar.current
        return String(format: "%02d·%03d", cal.component(.year, from: date) % 100, cal.ordinality(of: .day, in: .year, for: date)!)
    }
    public func file(_ date: Date) -> URL { vault.appendingPathComponent("datodine/\(dateName(date)).md") }
    func template(_ date: Date) -> String {
        "# \(dateName(date))\n\n[[Home]] · [[priorities]]\n\nredclub\n\nblueclub\n\nwhiteclub\n\ngoldclub\n\nlogs\n\nwhat got done / where to start next\n"
    }
    public func write(id: String, date: Date, text: String) throws {
        let path = file(date)
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        var content = FileManager.default.fileExists(atPath: path.path) ? try String(contentsOf: path, encoding: .utf8) : template(date)
        let indexURL = vault.appendingPathComponent(".laps-index.json")
        var index: [String: String] = [:]
        if FileManager.default.fileExists(atPath: indexURL.path) {
            index = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: indexURL))
        }
        let formatter = DateFormatter(); formatter.dateFormat = "H:mm"
        let clean = text.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
        guard !clean.isEmpty else { return }
        let entry = "\(formatter.string(from: date)) \(clean)"
        let key = dateName(date) + "/" + id
        if let old = index[key], let range = content.range(of: "(?m)^" + NSRegularExpression.escapedPattern(for: old) + "\n", options: .regularExpression) {
            content.replaceSubrange(range, with: entry + "\n")
        } else {
            if content.range(of: "(?m)^logs\\s*$", options: .regularExpression) == nil { content += "\nlogs\n" }
            if let summary = content.range(of: "(?m)^what got done / where to start next", options: .regularExpression) {
                content.insert(contentsOf: entry + "\n\n", at: summary.lowerBound)
            } else { content += "\n" + entry + "\n" }
        }
        index[key] = entry
        try content.write(to: path, atomically: true, encoding: .utf8)
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
    }
}
