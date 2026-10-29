import Foundation

/// Parses comma-separated task labels, removing empty entries and case-insensitive duplicates.
public enum TaskLabels {
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
