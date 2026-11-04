import AppKit
import SwiftUI

// Tabs whose page is in Google Chrome, opened with ⌃⌘T (Settings › Tabs).
//
// Search draws its pages with WebKit and can't show Chrome's, so a Chrome tab
// is a tab Search keeps the way it keeps any other: a row, a title, an
// address, sleep and wake, ⌘W. Only the page lives elsewhere. Chrome is driven
// the way any script drives it, over Apple Events, and every tab is found again
// by its id. A new tab opens in the Chrome profile already open, so sign-ins,
// bookmarks and sync are Chrome's own; Search keeps none of them.
//
// While a Chrome tab is awake Chrome is asked what it has, every few seconds
// and off the main thread, because AppleScript waits on the app. A tab Chrome
// no longer has (closed there, or Chrome quit) sleeps in Search with its
// address, as a tab does when it is let go, and wakes in Chrome when looked at.
//
// Hibernating a Chrome tab closes it in Chrome, and quits Chrome if no Chrome
// tab is left awake: the rule asked for, so Chrome doesn't run for nothing.
// Closing the tab in Search closes its Chrome tab and leaves Chrome running.

// Main-actor, like the tabs it drives. Only the scripts leave the main thread
// (see run), and what they answer is handed back on it.
@MainActor
enum ChromeTabs {
    nonisolated static let bundleID = "com.google.Chrome"

    /// Chrome's answer to a script that couldn't be made to work.
    enum Failure: Error {
        /// Search isn't allowed to control Chrome yet (Automation in Privacy).
        case notAllowed
        /// No windowed Chrome to ask. Nothing was sent to anything else.
        case notRunning
        case failed(String)
    }

    /// One tab as Chrome lists it: its id, where it is, and its title.
    struct Row: Equatable {
        let id: String
        let url: String
        let title: String
    }

    /// Serial, so scripts run one after another in the order they were asked:
    /// a close asked before a quit happens before it.
    private static let queue = DispatchQueue(label: "com.officecommun.search.chrome")
    private static var timer: Timer?
    private static var reading = false
    private static var askedToAllow = false

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    /// The Chrome processes running, as their command lines. Apple Events go to
    /// Chrome by bundle ID, and a headless Chrome another tool started (with a
    /// debugging port) answers to that ID too, in a window nobody can see. So
    /// what counts as Chrome running is the one a person would see.
    nonisolated static func chromeCommandLines() -> [String] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-axo", "args="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        do { try ps.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("/Google Chrome.app/Contents/MacOS/Google Chrome") && !$0.contains("--type=") }
    }

    /// A Chrome a person would see running.
    nonisolated static func windowedChromeRunning() -> Bool {
        chromeCommandLines().contains { !isHeadless($0) }
    }

    /// A headless Chrome, or one started with a debugging port: another tool's,
    /// as a rule. Search never drives one and never quits one.
    nonisolated static func isHeadless(_ commandLine: String) -> Bool {
        commandLine.contains("--headless") || commandLine.contains("--remote-debugging")
    }

    /// Whether a headless Chrome is running next to any windowed one. Quitting
    /// Chrome then could reach the headless one, so Search doesn't.
    nonisolated static func headlessChromeRunning() -> Bool {
        chromeCommandLines().contains { isHeadless($0) }
    }

    static var isFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    static var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(named: NSImage.applicationIconName) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: - Tabs in Search

    /// Every tab Search keeps in Chrome that is awake: opening, or open there.
    /// Sleeping and closed tabs are not in it.
    static func awakeTabs() -> [Tab] {
        Browsers.all.flatMap { $0.tabs + $0.parkedTabs }.filter { $0.inChrome && !$0.asleep }
    }

    /// Opens a tab in Chrome at `url`, or at Chrome's new tab page when there is
    /// none. Chrome is started if it isn't running; brought forward only when
    /// `activate` says so, as ⌃⌘T does and waking a tab in Search does not.
    static func attach(_ tab: Tab, url: URL?, activate: Bool) {
        guard isInstalled else {
            tab.chromeFailed()
            report("Google Chrome isn't installed on this Mac.")
            return
        }
        watch()
        run(openScript(url, activate: activate), starting: true) { result in
            switch result {
            case .success(let id) where !id.isEmpty:
                NSLog("ChromeTabs: opened tab %@", id)
                tab.chromeOpened(id)
            case .success:
                tab.chromeFailed()
                report("Chrome didn't say which tab it made.")
            case .failure(.notAllowed):
                tab.chromeFailed()
                explainDenied()
            case .failure(.notRunning):
                tab.chromeFailed()
                report("Google Chrome didn't start.")
            case .failure(.failed(let why)):
                NSLog("ChromeTabs: open failed: %@", why)
                tab.chromeFailed()
                report(why)
            }
        }
    }

    /// Closes a Chrome tab. With `quitWhenNoneLeft`, Chrome quits after it when
    /// no other tab Search keeps in Chrome is awake (see the top of this file).
    /// The caller has already taken this tab out of the awake set.
    static func release(_ id: String, quitWhenNoneLeft: Bool) {
        run(onTab(id, "close t")) { _ in }
        if quitWhenNoneLeft, awakeTabs().isEmpty { quit() }
    }

    static func navigate(_ id: String, to url: URL) {
        run(onTab(id, "set URL of t to \(quote(url.absoluteString))")) { _ in }
    }

    static func reload(_ id: String) {
        run(onTab(id, "tell t to reload")) { _ in }
    }

    /// Brings Chrome forward on the tab, for the stand-in's button.
    static func show(_ id: String) {
        run(onTab(id, """
            set active tab index of w to i
            set index of w to 1
            activate
            """)) { _ in }
    }

    /// Chrome quits only when it is the one a person sees and no headless Chrome
    /// runs beside it: the Apple Event would reach whichever one it picked.
    static func quit() {
        guard windowedChromeRunning(), !headlessChromeRunning() else { return }
        run("tell application id \"\(bundleID)\" to quit") { _ in }
    }

    // MARK: - Keeping up with Chrome

    /// Starts the look at Chrome, once. It stops itself when no Chrome tab is
    /// awake any more (see refresh).
    static func watch() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { ChromeTabs.refresh() }
        }
    }

    /// Asks Chrome for its tabs and brings every awake Chrome tab up to date:
    /// its address and title, whether it is the one being looked at, and
    /// whether it is still there. A look that is still running is not started
    /// again, and one that finds Chrome not running lets every tab go to sleep
    /// without waiting for the answer.
    static func refresh() {
        let watched: [(tab: Tab, id: String)] = awakeTabs().compactMap { tab in
            tab.chromeTab.map { (tab, $0) }
        }
        guard !watched.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard !reading else { return }
        reading = true
        run(snapshotScript) { result in
            reading = false
            switch result {
            case .success(let text):
                let snapshot = parse(text)
                let frontmost = isFrontmost
                NSLog("ChromeTabs look: %d watched, %d rows, front %@",
                      watched.count, snapshot.rows.count, snapshot.front ?? "none")
                for (tab, id) in watched where tab.chromeTab == id {
                    if let row = snapshot.rows.first(where: { $0.id == id }) {
                        tab.chromeSaid(url: URL(string: row.url), title: row.title,
                                       inFront: frontmost && snapshot.front == id)
                    } else {
                        NSLog("ChromeTabs look: tab %@ is gone", id)
                        tab.leaveChrome()
                    }
                }
            case .failure(.notRunning):
                // No windowed Chrome: none of the tabs in it is there any more.
                for (tab, id) in watched where tab.chromeTab == id { tab.leaveChrome() }
            case .failure(.notAllowed):
                explainDenied()
            case .failure(let why):
                NSLog("ChromeTabs look failed: %@", String(describing: why))
            }
        }
    }

    /// The first line is the id of the tab in front in Chrome's front window,
    /// empty when there is none; each line after is one tab. A title can hold a
    /// tab character, so each line splits into three at most, and a line that
    /// doesn't come out whole is skipped rather than guessed at.
    static func parse(_ text: String) -> (front: String?, rows: [Row]) {
        var lines = text.components(separatedBy: "\n")
        let front = lines.isEmpty ? "" : lines.removeFirst()
        let rows = lines.compactMap { line -> Row? in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            return Row(id: String(parts[0]), url: String(parts[1]), title: String(parts[2]))
        }
        return (front.isEmpty ? nil : front, rows)
    }

    // MARK: - Scripts

    /// The text of an AppleScript string, quoted: a backslash or a quote in it
    /// is escaped, so an address can't end the script early.
    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func openScript(_ url: URL?, activate: Bool) -> String {
        let properties = url.map { " with properties {URL:\(quote($0.absoluteString))}" } ?? ""
        return """
        tell application id "\(bundleID)"
            \(activate ? "activate" : "")
            if (count of windows) is 0 then make new window
            set w to front window
            set t to make new tab at end of tabs of w\(properties)
            set active tab index of w to (count of tabs of w)
            return (id of t) as text
        end tell
        """
    }

    /// Every tab as "id<TAB>url<TAB>title" on its own line, after the id of the
    /// tab in front. Characters are written by code, not as tab and return
    /// words, which Chrome's own tab class would otherwise answer to.
    static var snapshotScript: String {
        """
        tell application id "\(bundleID)"
            set out to ""
            try
                set out to ((id of active tab of front window) as text) & (character id 10)
            on error
                set out to (character id 10)
            end try
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        set out to out & ((id of t) as text) & (character id 9) & ((URL of t) as text) & (character id 9) & ((title of t) as text) & (character id 10)
                    end try
                end repeat
            end repeat
            return out
        end tell
        """
    }

    /// Runs `action` on the tab with `id`, with `t` the tab, `w` its window and
    /// `i` its place in that window. Returns "missing" when Chrome no longer has it.
    private static func onTab(_ id: String, _ action: String) -> String {
        """
        tell application id "\(bundleID)"
            repeat with w in windows
                set i to 0
                repeat with t in tabs of w
                    set i to i + 1
                    if ((id of t) as text) is \(quote(id)) then
                        \(action)
                        return "ok"
                    end if
                end repeat
            end repeat
            return "missing"
        end tell
        """
    }

    // MARK: - Running scripts

    /// Starts a windowed Chrome, as its own instance. `open` alone would hand the
    /// request to a headless Chrome that is already running.
    nonisolated private static func launchChrome() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-a", app.path]
        do { try open.run() } catch { return }
        open.waitUntilExit()
    }

    /// Compiles and runs a script on the queue, and hands the answer to `done`
    /// on the main thread. A script goes only to a windowed Chrome: with
    /// `starting`, one is started first and the script waits for it to be up;
    /// without, a Chrome that isn't there is not asked, since asking starts one.
    /// Errors come back as Failure: the Automation refusal is its own case,
    /// since it is the one the person can fix.
    private static func run(_ source: String, starting: Bool = false, _ done: @escaping (Result<String, Failure>) -> Void) {
        queue.async {
            if starting, !windowedChromeRunning() { launchChrome() }
            let deadline = Date().addingTimeInterval(starting ? 20 : 0)
            while !windowedChromeRunning(), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.25)
            }
            guard windowedChromeRunning() else {
                DispatchQueue.main.async { done(.failure(.notRunning)) }
                return
            }
            var error: NSDictionary?
            let output = NSAppleScript(source: source)?.executeAndReturnError(&error)
            let result: Result<String, Failure>
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                if number == -1743 {
                    result = .failure(.notAllowed)
                } else {
                    let message = error[NSAppleScript.errorMessage] as? String
                    result = .failure(.failed(message ?? "Google Chrome didn't answer."))
                }
            } else {
                result = .success(output?.stringValue ?? "")
            }
            DispatchQueue.main.async { done(result) }
        }
    }

    // MARK: - Telling the person

    private static func explainDenied() {
        guard !askedToAllow else { return }
        askedToAllow = true
        let alert = NSAlert()
        alert.messageText = "Search can't control Google Chrome"
        alert.informativeText = "Allow Search to control Google Chrome under Privacy & Security › Automation in System Settings, then try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func report(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Google Chrome didn't open the tab"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

/// What a tab shows while its page is in Google Chrome: where it is, and a way
/// to Chrome. Drawn where the page would be, and not a web view at all.
struct ChromeStandIn: View {
    @ObservedObject var tab: Tab

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: ChromeTabs.icon)
                .resizable()
                .frame(width: 44, height: 44)
            Text(tab.label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if let address = tab.address {
                Text(Address.pretty(address))
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            if let id = tab.chromeTab {
                Text("This page is open in Google Chrome.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Button("Show in Google Chrome") { ChromeTabs.show(id) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
            } else if tab.asleep {
                // Chrome let its tab go while it was on screen. Opening it again
                // is the person's call, not something to do on their behalf.
                Text("This page was closed in Google Chrome.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                Button("Open in Google Chrome") { _ = tab.wake() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
            } else {
                Text("Opening in Google Chrome…")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
    }
}
