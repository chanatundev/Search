import XCTest
@testable import Search

/// A space's tabs belong to the space. A second window can show Business
/// while the first stays on Academics, and opening it does not replace
/// either row with an empty one.
@MainActor
final class SpaceWindowTests: XCTestCase {
    private var previousSpaces: [Space] = []
    private var previousUsesSpaces = false

    override class func setUp() {
        // Before anything reads Store: a test run stays out of the real profile.
        setenv("SEARCH_PROBE", "space-windows-\(getpid())", 1)
        super.setUp()
    }

    override func setUp() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        previousSpaces = Spaces.read()
        previousUsesSpaces = Shared.prefs.usesSpaces
        Shared.prefs.usesSpaces = true
    }

    override func tearDown() async throws {
        Shared.prefs.usesSpaces = previousUsesSpaces
        Spaces.write(previousSpaces)
        XCTAssertTrue(NSApp.windows.allSatisfy { !$0.isVisible })
    }

    func testNewWindowShowsBusinessWithoutClearingAcademics() throws {
        XCTAssertTrue(Store.testing)
        XCTAssertTrue(Store.folder.path.contains("Search ("))
        let academics = Space(id: UUID(), name: "Academics", colour: 1, icon: "graduationcap")
        let business = Space(id: UUID(), name: "Business", colour: 2, icon: "briefcase")
        Spaces.write([
            Space(id: Space.firstID, name: "Personal", colour: 0),
            academics,
            business,
        ])

        var kept = WindowRecord(space: academics.id)
        kept.rows[academics.id.uuidString] = Session.Shape(
            tabs: [Session.Entry(url: "https://school.example/", title: "School")],
            active: 0
        )
        kept.rows[business.id.uuidString] = Session.Shape(
            tabs: [Session.Entry(url: "https://work.example/", title: "Work")],
            active: 0
        )
        let first = Browser(record: kept)
        Browsers.register(first)
        let school = try XCTUnwrap(first.tabs.first { $0.address?.host == "school.example" })
        let work = try XCTUnwrap(first.parked[business.id]?.tabs.first { $0.address?.host == "work.example" })

        let second = Browser(record: WindowRecord(space: academics.id))
        Browsers.register(second)
        XCTAssertEqual(first.tabs.map(\.id), [school.id])

        second.switchSpace(to: business.id)

        XCTAssertTrue(second.tabs.contains { $0.id == work.id })
        XCTAssertEqual(first.tabs.map(\.id), [school.id])
        XCTAssertNil(first.parked[business.id])
    }
}
