import Foundation

/// Pure ordering helpers shared by UI actions and unit tests.
public enum TaskOrdering {
    public static func normalizedOrders(count: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(0..<count)
    }

    public static func insertionIndex(proposed: Int, count: Int) -> Int {
        min(max(0, proposed), count)
    }

    /// Returns a new array with the item moved to the requested insertion offset.
    public static func moving<Item: Equatable>(_ item: Item, in items: [Item], to proposedOffset: Int) -> [Item] {
        guard let source = items.firstIndex(of: item) else { return items }
        var result = items
        result.remove(at: source)
        result.insert(item, at: insertionIndex(proposed: proposedOffset, count: result.count))
        return result
    }

    public static func moving<Item: Equatable>(
        _ item: Item,
        from source: [Item],
        to destination: [Item],
        at proposedOffset: Int
    ) -> (source: [Item], destination: [Item]) {
        guard let sourceIndex = source.firstIndex(of: item) else { return (source, destination) }
        var updatedSource = source
        var updatedDestination = destination
        updatedSource.remove(at: sourceIndex)
        updatedDestination.insert(item, at: insertionIndex(proposed: proposedOffset, count: updatedDestination.count))
        return (updatedSource, updatedDestination)
    }
}
