import XCTest
import JungoCore

final class TaskOrderingTests: XCTestCase {
    func testNormalizedOrdersAreContiguous() {
        XCTAssertEqual(TaskOrdering.normalizedOrders(count: 0), [])
        XCTAssertEqual(TaskOrdering.normalizedOrders(count: 1), [0])
        XCTAssertEqual(TaskOrdering.normalizedOrders(count: 4), [0, 1, 2, 3])
    }

    func testInsertionIndexIsClampedToValidRange() {
        XCTAssertEqual(TaskOrdering.insertionIndex(proposed: -4, count: 3), 0)
        XCTAssertEqual(TaskOrdering.insertionIndex(proposed: 1, count: 3), 1)
        XCTAssertEqual(TaskOrdering.insertionIndex(proposed: 9, count: 3), 3)
        XCTAssertEqual(TaskOrdering.insertionIndex(proposed: 0, count: 0), 0)
    }

    func testMovingWithinCollection() {
        XCTAssertEqual(TaskOrdering.moving("b", in: ["a", "b", "c"], to: 2), ["a", "c", "b"])
        XCTAssertEqual(TaskOrdering.moving("c", in: ["a", "b", "c"], to: 0), ["c", "a", "b"])
        XCTAssertEqual(TaskOrdering.moving("missing", in: ["a", "b"], to: 0), ["a", "b"])
    }

    func testMovingBetweenCollections() {
        let result = TaskOrdering.moving("b", from: ["a", "b", "c"], to: ["x", "y"], at: 1)
        XCTAssertEqual(result.source, ["a", "c"])
        XCTAssertEqual(result.destination, ["x", "b", "y"])
        XCTAssertEqual(result.source.count + result.destination.count, 5)
    }

    func testMovingIntoEmptyCollection() {
        let result = TaskOrdering.moving("a", from: ["a"], to: [], at: 99)
        XCTAssertEqual(result.source, [])
        XCTAssertEqual(result.destination, ["a"])
    }
}
