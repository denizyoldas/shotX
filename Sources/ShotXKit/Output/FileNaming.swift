import Foundation

/// `shotX 2026-11-11 at 14.05.09.png`, then ` 2`, ` 3`… when the name is taken. The returned URL does not exist yet.
nonisolated enum FileNaming {
    static func url(in directory: URL, date: Date, ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "shotX \(formatter.string(from: date))"

        var candidate = directory.appendingPathComponent("\(base).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
