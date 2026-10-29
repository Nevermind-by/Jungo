import Foundation

public enum TaskOrdering {
    public static func normalizedOrders(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(0..<count)
    }

    public static func insertionIndex(proposed: Int, count: Int) -> Int {
        min(max(0, proposed), count)
    }
}
