import XCTest
@testable import Search

/// Google Chrome tabs (⌃⌘T): what Chrome's answer means, how the scripts are
/// written, and how a Search tab follows its page once Chrome has it. Nothing
/// here opens or closes a tab in a real Chrome: that would start Chrome from a
/// test run. The states are set by hand instead.
@MainActor
final class ChromeTabsTests: XCTestCase {
    private let example = URL(string: "https://example.com/")!

    override func setUp() {
        super.setUp()
        // A tab's icon reads the app's appearance, which needs an application.
        _ = NSApplication.shared
    }

    // MARK: - Chrome's answer

    func testParseReadsTheFrontTabAndEveryRow() {
        let parsed = ChromeTabs.parse("7\n7\thttps://example.com/\tExample\n9\thttps://news.example/\tNews\n")
        XCTAssertEqual(parsed.front, "7")
        XCTAssertEqual(parsed.rows, [
            ChromeTabs.Row(id: "7", url: "https://example.com/", title: "Example"),
            ChromeTabs.Row(id: "9", url: "https://news.example/", title: "News"),
        ])
    }

    func testParseHasNoFrontTabWhenChromeHasNoWindow() {
        let parsed = ChromeTabs.parse("\n3\thttps://a.example/\tA\n")
        XCTAssertNil(parsed.front)
        XCTAssertEqual(parsed.rows.map(\.id), ["3"])
    }

    func testParseKeepsATabCharacterInATitle() {
        let parsed = ChromeTabs.parse("\n3\thttps://a.example/\tA\tB\n")
        XCTAssertEqual(parsed.rows.first?.title, "A\tB")
    }

    func testParseSkipsLinesThatDoNotComeOutWhole() {
        let parsed = ChromeTabs.parse("5\n\tno id here\n4\thttps://b.example/\tB\nnot a row\n")
        XCTAssertEqual(parsed.rows.map(\.id), ["4"])
    }

    // MARK: - The scripts

    func testQuoteEscapesQuotesAndBackslashes() {
        XCTAssertEqual(ChromeTabs.quote(#"a"b\c"#), #""a\"b\\c""#)
    }

    func testOpenScriptNamesTheAddressOnlyWhenThereIsOne() {
        let url = URL(string: "https://example.com/a?q=1")!
        XCTAssertTrue(ChromeTabs.openScript(url, activate: false)
            .contains(#"with properties {URL:"https://example.com/a?q=1"}"#))
        XCTAssertFalse(ChromeTabs.openScript(nil, activate: false).contains("with properties"))
    }

    func testOpenScriptBringsChromeForwardOnlyWhenAsked() {
        XCTAssertTrue(ChromeTabs.openScript(nil, activate: true).contains("activate"))
        XCTAssertFalse(ChromeTabs.openScript(nil, activate: false).contains("activate"))
    }

    // MARK: - A tab that lives in Chrome

    func testLeavingChromeKeepsTheAddressToWakeWith() {
        let tab = Tab()
        tab.restore(url: example, title: "Example")
        tab.restoreInChrome(tabID: "7")
        XCTAssertTrue(tab.inChrome)
        XCTAssertFalse(tab.asleep)
        XCTAssertEqual(tab.chromeTab, "7")

        XCTAssertEqual(tab.leaveChrome(), "7")
        XCTAssertNil(tab.chromeTab)
        XCTAssertTrue(tab.asleep)
        XCTAssertEqual(tab.address, example)
    }

    func testAFailedOpenLeavesAnAddressedTabAsleep() {
        let tab = Tab()
        tab.restore(url: example, title: "Example")
        tab.restoreInChrome(tabID: "7")
        tab.chromeFailed()
        XCTAssertTrue(tab.inChrome)
        XCTAssertTrue(tab.asleep)
        XCTAssertNil(tab.chromeTab)
    }

    func testChromeSayingWhereATabIsMovesItsAddressAndTitle() {
        let tab = Tab()
        tab.restore(url: example, title: "Example")
        tab.restoreInChrome(tabID: "7")
        tab.chromeSaid(url: URL(string: "https://example.com/next"), title: "Next", inFront: false)
        XCTAssertEqual(tab.address, URL(string: "https://example.com/next"))
        XCTAssertEqual(tab.label, "Next")
        XCTAssertFalse(tab.chromeInFront)
    }

    func testTheTabInFrontInChromeIsLookedAtSoItsClockRuns() {
        let tab = Tab()
        tab.restore(url: example, title: "Example")
        tab.restoreInChrome(tabID: "7")
        tab.touch(at: Date(timeIntervalSince1970: 0))
        tab.chromeSaid(url: nil, title: "Example", inFront: true)
        XCTAssertTrue(tab.chromeInFront)
        XCTAssertGreaterThan(tab.touched, Date(timeIntervalSince1970: 0))
    }

    func testAPageThatIsNotInChromeIsLeftAloneByLeavingChrome() {
        let tab = Tab()
        XCTAssertNil(tab.leaveChrome())
        XCTAssertFalse(tab.inChrome)
        XCTAssertFalse(tab.asleep)
    }

    func testAChromeTabWithNoAddressIsNoLongerAChromeTab() {
        let tab = Tab()
        tab.restoreInChrome(tabID: nil)
        XCTAssertFalse(tab.inChrome)
    }

    // MARK: - Sessions

    func testSessionKeepsTheChromeTabsId() throws {
        let entry = Session.Entry(url: "https://example.com/", title: "Example", chrome: true, chromeTab: "7")
        let data = try JSONEncoder().encode(entry)
        let back = try JSONDecoder().decode(Session.Entry.self, from: data)
        XCTAssertEqual(back.chrome, true)
        XCTAssertEqual(back.chromeTab, "7")
    }

    func testSessionFromBeforeChromeTabsReadsAsWebKitTabs() throws {
        let old = Data(#"{"url":"https://example.com/","title":"Example"}"#.utf8)
        let entry = try JSONDecoder().decode(Session.Entry.self, from: old)
        XCTAssertNil(entry.chrome)
        XCTAssertNil(entry.chromeTab)
    }

    // MARK: - Which Chrome

    func testHeadlessAndDebuggingChromeAreNotTheOneThePersonSees() {
        let windowed = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        let headless = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome --headless=new --remote-debugging-port=9724 --user-data-dir=/tmp/x about:blank"
        XCTAssertFalse(ChromeTabs.isHeadless(windowed))
        XCTAssertTrue(ChromeTabs.isHeadless(headless))
    }

    // MARK: - The key

    func testControlCommandTOpensAGoogleChromeTabAndIsOffUnlessAsked() {
        // KeyCombo's command defaults to on, so the displayed string is what
        // pins the modifiers: a comparison with the same expression proves nothing.
        XCTAssertEqual(Command.named("tabs.chrome")?.defaultKey?.display, "⌃⌘T")
        XCTAssertFalse(KeyCombo.isReserved(KeyCombo("t", control: true)))
        XCTAssertTrue(Command.chrome.contains("tabs.chrome"))
    }
}
