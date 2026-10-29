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
}
