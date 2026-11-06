import AppKit
import XCTest
@testable import Search

@MainActor
final class TabGroupDropTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "tab-group-drop-\(getpid())", 1)
        super.setUp()
    }

    private func makeBrowser() -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        browser.leaveFiles()
        browser.closeAll()
        browser.tabGroups = []
        browser.record.rows = [:]
        browser.parked = [:]
        return browser
    }

    func testPositionalMovesAndSourceCleanup() throws {
        let browser = makeBrowser()
        let grouped = browser.prefs.usesTabGroups
        let split = browser.prefs.splitView
        defer {
            browser.prefs.usesTabGroups = grouped
            browser.prefs.splitView = split
        }
        browser.prefs.usesTabGroups = true
        for number in 0..<6 {
            browser.newTab()
            browser.tabs.last?.restore(url: URL(string: "https://\(number).example/")!, title: "\(number)")
        }
        let tabs = browser.tabs
        let group = browser.addTabGroup(containing: tabs[0])
        for tab in tabs[1...2] { browser.move(tab, toGroup: group) }
        browser.move(tabs[3], toGroup: GroupDropTarget(group: group, member: tabs[0].id))
        browser.move(tabs[4], toGroup: GroupDropTarget(group: group, member: tabs[1].id))
        let source = browser.addTabGroup(containing: tabs[5])
        let active = browser.activeID
        browser.move(tabs[5], toGroup: GroupDropTarget(group: group, member: tabs[2].id, after: true))
        XCTAssertEqual(browser.tabs(in: group).map(\.id), [3, 0, 4, 1, 2, 5].map { tabs[$0].id })
        XCTAssertFalse(browser.tabGroups.contains { $0.id == source })
        XCTAssertEqual(browser.activeID, active)

        browser.move(tabs[3], toGroup: GroupDropTarget(group: group, member: tabs[5].id, after: true))
        browser.move(tabs[3], toGroup: GroupDropTarget(group: group, member: tabs[0].id))
        browser.move(tabs[4], toGroup: GroupDropTarget(group: group, member: tabs[1].id, after: true))
        let order = [3, 0, 1, 4, 2, 5].map { tabs[$0].id }
        XCTAssertEqual(browser.tabs.map(\.id), order)
        browser.move(tabs[4], toGroup: GroupDropTarget(group: group, member: tabs[4].id))
        browser.move(tabs[4], toGroup: GroupDropTarget(group: UUID()))
        browser.move(tabs[4], toGroup: GroupDropTarget(group: group, member: UUID()))
        XCTAssertEqual(browser.tabs.map(\.id), order)
        let foreign = Tab(configuration: Web.configuration())
        browser.move(foreign, toGroup: GroupDropTarget(group: group))
        tabs[4].pin = "pin"
        browser.move(tabs[4], toGroup: GroupDropTarget(group: group))
        tabs[4].pin = nil
        XCTAssertEqual(browser.tabs.map(\.id), order)
        browser.toggleTabGroup(group)
        browser.move(tabs[3], toGroup: GroupDropTarget(group: group))
        XCTAssertFalse(browser.tabGroups[0].collapsed)
        XCTAssertEqual(browser.tabs.last?.id, tabs[3].id)

        browser.prefs.splitView = true
        browser.pair(tabs[1], with: tabs[0], onLeft: false)
        browser.move(tabs[0], toGroup: GroupDropTarget(group: group))
        XCTAssertEqual(Array(browser.tabs.suffix(2)).map(\.id), [tabs[0].id, tabs[1].id])
        browser.move(tabs[1], toGroup: GroupDropTarget(group: group, member: tabs[4].id), detaching: true)
        XCTAssertEqual(browser.tabs.first?.id, tabs[1].id)
        XCTAssertEqual(browser.tabs.last?.id, tabs[0].id)
        XCTAssertNil(browser.split(for: tabs[1]))
        let saved = try XCTUnwrap(browser.record.rows[browser.spaceID.uuidString])
        let restored = Browser(record: browser.record)
        XCTAssertEqual(restored.tabs.map { $0.address?.absoluteString }, saved.tabs.map { Optional($0.url) })
        XCTAssertEqual(restored.tabs.map(\.groupID), saved.tabs.map(\.groupID))
    }

    func testVisibleGeometryInBothLayouts() {
        let group = TabGroup(id: UUID(), name: "Group", collapsed: false)
        let first = UUID(), last = UUID(), source = UUID()
        // Unequal lengths and a negative origin also exercise scrolled coordinates.
        for vertical in [false, true] {
            let rect: (CGFloat, CGFloat) -> CGRect = { start, length in
                vertical ? CGRect(x: 10, y: start, width: 80, height: length)
                    : CGRect(x: start, y: 10, width: length, height: 80)
            }
            let point: (CGFloat) -> CGPoint = { position in
                vertical ? CGPoint(x: 30, y: position) : CGPoint(x: position, y: 30)
            }
            let frames = [
                group.id: GroupDropFrame(group: group.id, rect: rect(-40, 20)),
                first: GroupDropFrame(group: group.id, tab: first, rect: rect(-10, 30)),
                last: GroupDropFrame(group: group.id, tab: last, rect: rect(30, 80)),
                source: GroupDropFrame(group: group.id, tab: source, rect: rect(120, 30))
            ]
            for (position, target) in [
                (-30.0, GroupDropTarget(group: group.id)),
                (-5.0, GroupDropTarget(group: group.id, member: first)),
                (25.0, GroupDropTarget(group: group.id, member: last)),
                (100.0, GroupDropTarget(group: group.id, member: last, after: true))
            ] {
                XCTAssertEqual(GroupDropFrames.resolve(point(position), frames: frames, groups: [group],
                                                       excluding: source, vertical: vertical), target)
            }
            XCTAssertNil(GroupDropFrames.resolve(point(140), frames: frames, groups: [group],
                                                 excluding: source, vertical: vertical))
            var collapsed = group
            collapsed.collapsed = true
            XCTAssertEqual(GroupDropFrames.resolve(point(40), frames: frames, groups: [collapsed],
                                                    excluding: source, vertical: vertical), GroupDropTarget(group: group.id))
        }
    }

    func testMultiTabGroupCreationAndMovement() throws {
        let browser = makeBrowser()
        let grouped = browser.prefs.usesTabGroups
        defer { browser.prefs.usesTabGroups = grouped }
        browser.prefs.usesTabGroups = true

        for number in 0..<6 {
            browser.newTab()
            browser.tabs.last?.restore(url: URL(string: "https://\(number).example/")!, title: "\(number)")
        }
        let tabs = browser.tabs

        let group1 = browser.addTabGroup(containing: [tabs[1], tabs[2], tabs[4]])
        XCTAssertEqual(browser.tabGroups.count, 1)
        XCTAssertEqual(browser.tabs(in: group1).map(\.id), [tabs[1].id, tabs[2].id, tabs[4].id])
        XCTAssertEqual(tabs[1].groupID, group1)
        XCTAssertEqual(tabs[2].groupID, group1)
        XCTAssertEqual(tabs[4].groupID, group1)
        XCTAssertNil(tabs[0].groupID)
        XCTAssertNil(tabs[3].groupID)
        XCTAssertNil(tabs[5].groupID)

        browser.move([tabs[0], tabs[3]], toGroup: group1)
        XCTAssertEqual(tabs[0].groupID, group1)
        XCTAssertEqual(tabs[3].groupID, group1)
        XCTAssertEqual(browser.tabs(in: group1).count, 5)

        let group2 = browser.addTabGroup(containing: [tabs[0], tabs[1]])
        XCTAssertEqual(browser.tabGroups.count, 2)
        XCTAssertEqual(browser.tabs(in: group2).map(\.id), [tabs[1].id, tabs[0].id])
        XCTAssertEqual(browser.tabs(in: group1).map(\.id), [tabs[2].id, tabs[4].id, tabs[3].id])

        browser.move([tabs[2], tabs[4]], toGroup: nil)
        XCTAssertNil(tabs[2].groupID)
        XCTAssertNil(tabs[4].groupID)
        XCTAssertEqual(browser.tabs(in: group1).map(\.id), [tabs[3].id])

        browser.move([tabs[3]], toGroup: nil)
        XCTAssertNil(tabs[3].groupID)
        XCTAssertFalse(browser.tabGroups.contains { $0.id == group1 })
        XCTAssertEqual(browser.tabGroups.count, 1)
        XCTAssertEqual(browser.tabGroups.first?.id, group2)
    }

    func testMultiTabDropMovement() throws {
        let browser = makeBrowser()
        let grouped = browser.prefs.usesTabGroups
        defer { browser.prefs.usesTabGroups = grouped }
        browser.prefs.usesTabGroups = true

        for number in 0..<6 {
            browser.newTab()
            browser.tabs.last?.restore(url: URL(string: "https://\(number).example/")!, title: "\(number)")
        }
        let tabs = browser.tabs
        let group = browser.addTabGroup(containing: tabs[0])

        browser.select(tabs[1])
        browser.extendTabSelection(to: tabs[2], modifiers: .command)
        XCTAssertEqual(browser.selectedTabIDs, Set([tabs[1].id, tabs[2].id]))

        browser.move(tabs[1], toGroup: GroupDropTarget(group: group, member: tabs[0].id, after: true))
        XCTAssertEqual(browser.tabs(in: group).map(\.id), [tabs[0].id, tabs[1].id, tabs[2].id])

        browser.select(tabs[4])
        browser.extendTabSelection(to: tabs[5], modifiers: .command)

        browser.move(tabs[5], toGroup: GroupDropTarget(group: group, member: tabs[0].id, after: false))
        XCTAssertEqual(browser.tabs(in: group).map(\.id), [tabs[4].id, tabs[5].id, tabs[0].id, tabs[1].id, tabs[2].id])
    }

    func testMultiTabResolveExclusion() {
        let group = TabGroup(id: UUID(), name: "Group", collapsed: false)
        let tabA = UUID(), tabB = UUID(), tabC = UUID()
        let rect: (CGFloat, CGFloat) -> CGRect = { start, length in
            CGRect(x: 10, y: start, width: 80, height: length)
        }
        let frames = [
            group.id: GroupDropFrame(group: group.id, rect: rect(-40, 20)),
            tabA: GroupDropFrame(group: group.id, tab: tabA, rect: rect(-10, 30)),
            tabB: GroupDropFrame(group: group.id, tab: tabB, rect: rect(30, 80)),
            tabC: GroupDropFrame(group: group.id, tab: tabC, rect: rect(120, 30))
        ]
        let point = CGPoint(x: 30, y: -5.0)
        let singleExclude = GroupDropFrames.resolve(point, frames: frames, groups: [group],
                                                   excluding: tabB, vertical: true)
        XCTAssertEqual(singleExclude, GroupDropTarget(group: group.id, member: tabA))

        let multiExclude = GroupDropFrames.resolve(point, frames: frames, groups: [group],
                                                  excluding: Set([tabA, tabB]), vertical: true)
        XCTAssertNotEqual(multiExclude?.member, tabA)
        XCTAssertNotEqual(multiExclude?.member, tabB)
    }
}
