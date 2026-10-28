import XCTest
@testable import Search

final class CloseWindowShortcutTests: XCTestCase {
    func testShiftCommandWClosesTheWindow() {
        let command = Command.named("file.closeWindow")
        XCTAssertEqual(command?.title, "Close Window")
        XCTAssertEqual(command?.defaultKey, KeyCombo("w", shift: true))
    }
}
