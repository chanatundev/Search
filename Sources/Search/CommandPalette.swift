import SwiftUI
import AppKit

/// Search's built-in actions, gathered in one place without giving them a
/// second implementation. ⌘E opens it from the menu or while a page has focus.
struct CommandPalette: View {
    @ObservedObject var browser: Browser
    @State private var query = ""
    @State private var selected = 0
    @State private var hoveredCommandID: String?
    @FocusState private var searchFocused: Bool

    private static let commandKeywords: [String: String] = [
        "file.newWindow": "window browser",
        "file.newTab": "tab",
        "file.newPrivateTab": "incognito private shy secret",
        "file.reopen": "undo restore closed tab",
        "file.openAddress": "url location bar omnibox go",
        "file.closeTab": "close w",
        "file.import": "bookmarks passwords history chrome arc brave safari",
        "file.print": "pdf hardcopy",
        "edit.find": "search page text in document",
        "view.sidebar": "left column tab list vertical",
        "view.fold": "toggle hide collapse sidebar bar",
        "view.reload": "refresh",
        "view.reloadOrigin": "hard refresh cache bypass",
        "view.reader": "article read clean mode",
        "view.float": "pip picture in picture floating video popup",
        "view.summarize": "ai summary tl;dr",
        "view.ask": "ai question explain page",
        "view.hide": "remove clutter ads blocker cosmetic",
        "view.hidden": "restore unhide elements rules",
        "view.zoomIn": "magnify larger text scale",
        "view.zoomOut": "smaller text scale",
        "view.actualSize": "reset 100% default scale",
        "view.inspector": "developer devtools inspect elements",
        "view.console": "developer js logs devtools error",
        "view.inspect": "developer pick element devtools",
        "tabs.split": "side by side dual pane two pages",
        "tabs.focusLeftPane": "pane left switch",
        "tabs.focusRightPane": "pane right switch",
        "tabs.focusOtherPane": "pane switch flip",
        "tabs.swapSplit": "reorder switch sides",
        "tabs.separateSplit": "unsplit join detach",
        "tabs.rename": "title label name",
        "tabs.duplicate": "clone copy tab",
        "tabs.copyAddress": "copy url link",
        "tabs.copyMarkdown": "link format md",
        "tabs.pasteAndGo": "clipboard open navigate",
        "tabs.closeOthers": "isolate only keep current",
        "tabs.mute": "silence sound audio pause",
        "bookmarks.add": "favorite star save",
        "bookmarks.show": "favorites list library",
        "bookmarks.bar": "shelf favorites row",
        "history.show": "recent visited sites library",
        "history.downloads": "files transfers loot fetched",
        "history.clearData": "cache cookies remove erase reset",
        "history.clear": "erase recent visits",
        "app.settings": "preferences config options",
        "app.passwords": "logins credentials keychain vault",
    ]

    private var spaceCommands: [PaletteCommand] {
        guard browser.prefs.usesSpaces else { return [] }
        return browser.spaces.enumerated().map { index, space in
            let number = index + 1
            return .init(
                "\(number). \(space.name)",
                section: "Spaces",
                shortcut: number <= 9 ? "\(number)" : nil,
                keywords: "space \(number) switch workspace",
                action: { browser.switchSpace(to: space.id) }
            )
        }
    }

    private var menuCommands: [PaletteCommand] {
        let active = browser.active
        let hasPage = active.map { !$0.isBlank } ?? false
        let hasSplit = active.flatMap { browser.split(for: $0) } != nil

        return Command.all.compactMap { command in
            // Skip palette trigger itself
            guard command.id != "app.palette" else { return nil }
            // Filter split commands if split view disabled
            if Command.split.contains(command.id), !browser.prefs.splitView { return nil }
            // Filter AI commands if AI disabled
            if Command.ai.contains(command.id), !browser.prefs.ai { return nil }

            let shortcut = ShortcutStore.shared.key(for: command.id)?.display

            let enabled: Bool
            switch command.id {
            case "file.reopen": enabled = !browser.ghosts.isEmpty
            case "file.closeTab": enabled = active != nil
            case "file.share", "file.print": enabled = hasPage
            case "edit.find", "edit.findNext", "edit.findPrevious": enabled = hasPage
            case "view.reload", "view.reloadOrigin", "view.reader", "view.float": enabled = hasPage
            case "view.summarize", "view.ask", "view.hide": enabled = hasPage
            case "view.hidden": enabled = browser.hereHost != nil
            case "view.zoomIn", "view.zoomOut", "view.actualSize": enabled = hasPage
            case "view.inspector", "view.console", "view.inspect": enabled = hasPage
            case "tabs.next", "tabs.previous": enabled = browser.tabs.count > 1
            case "tabs.split": enabled = hasPage && !hasSplit
            case "tabs.focusLeftPane", "tabs.focusRightPane", "tabs.focusOtherPane", "tabs.swapSplit", "tabs.separateSplit":
                enabled = hasSplit
            case "tabs.rename": enabled = active != nil
            case "tabs.duplicate": enabled = hasPage
            case "tabs.copyAddress": enabled = !browser.tabsWithAddressesToCopy.isEmpty
            case "tabs.copyMarkdown": enabled = hasPage
            case "tabs.closeOthers": enabled = browser.tabs.count > 1
            case "tabs.mute": enabled = active != nil
            case "bookmarks.add": enabled = hasPage
            default: enabled = true
            }

            let keywords = Self.commandKeywords[command.id] ?? ""

            return PaletteCommand(
                command.title,
                section: command.section.rawValue,
                shortcut: shortcut,
                keywords: keywords,
                enabled: enabled
            ) {
                command.run(browser)
            }
        }
    }

    private var extraCommands: [PaletteCommand] {
        let active = browser.active
        let hasPage = active.map { !$0.isBlank } ?? false
        let isFullscreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false

        var extras: [PaletteCommand] = []

        if let active {
            extras.append(.init(
                active.pin == nil ? "Pin Tab" : "Unpin Tab",
                section: "Tabs",
                keywords: "pin unpin anchor",
                enabled: hasPage,
                action: {
                    if active.pin == nil { browser.pin(active) } else { browser.unpin(active) }
                }
            ))
        }

        extras.append(.init(
            "Sleep Background Tabs",
            section: "Tabs",
            note: "Current space · tabs other than the one in front",
            keywords: "memory inactive hibernate suspend sleep",
            enabled: browser.tabs.count > 1,
            action: { browser.sleepBackgroundTabs() }
        ))

        extras.append(.init(
            "Sleep Background Spaces",
            section: "Tabs",
            note: browser.prefs.usesSpaces ? "Tabs parked in other spaces" : "Turn on Spaces in Settings first",
            keywords: "memory parked hibernate suspend sleep",
            enabled: browser.prefs.usesSpaces,
            action: { browser.sleepBackgroundSpaces() }
        ))

        extras.append(.init(
            isFullscreen ? "Exit Full Screen" : "Enter Full Screen",
            section: "Window",
            shortcut: "⌃⌘F",
            keywords: "enter exit fullscreen window",
            action: { NSApp.keyWindow?.toggleFullScreen(nil) }
        ))

        return extras
    }

    private var commands: [PaletteCommand] {
        spaceCommands + menuCommands + extraCommands
    }

    private var matches: [PaletteCommand] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return commands }
        return commands.filter { command in words.allSatisfy(command.matches) }
    }

    var body: some View {
        GeometryReader { geometry in
            panel
            .frame(width: min(540, geometry.size.width - 56), height: min(560, geometry.size.height - 48))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
        .onChange(of: query) { _, _ in
            selected = 0
            hoveredCommandID = nil
        }
    }

    private var panel: some View {
        VStack(spacing: 8) {
            searchField
            Rectangle().fill(Palette.hairline).frame(height: 1)
            commandList
            footer
        }
        .padding(12)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 26, y: 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.muted)
            TextField("Search commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(keys: Set((1...9).map { KeyEquivalent(Character(String($0))) })) { keyPress in
                    guard keyPress.modifiers.isDisjoint(with: [.command, .control, .option, .shift]),
                          browser.prefs.usesSpaces,
                          let number = Int(keyPress.characters),
                          browser.spaces.indices.contains(number - 1) else { return .ignored }
                    browser.commandPalette = false
                    browser.switchSpace(index: number - 1)
                    return .handled
                }
                .onSubmit(runSelected)
            Text("esc")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.muted)
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Palette.wash.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    if matches.isEmpty {
                        Text("No matching commands")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                            .frame(maxWidth: .infinity, minHeight: 64)
                    } else {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, command in
                            row(command, selected: command.id == hoveredCommandID || (hoveredCommandID == nil && index == selected))
                                .id(command.id)
                                .onHover { hovering in
                                    if hovering {
                                        hoveredCommandID = command.id
                                    } else if hoveredCommandID == command.id {
                                        hoveredCommandID = nil
                                    }
                                }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: selected) { _, index in
                guard matches.indices.contains(index) else { return }
                proxy.scrollTo(matches[index].id, anchor: .center)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("↑ ↓ Move    Return Run")
            Spacer()
            Text("\(matches.count) commands")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Palette.muted)
        .padding(.top, 2)
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        Button {
            run(command)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: command.note == nil ? 0 : 3) {
                    Text(command.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(command.enabled ? Palette.ink : Palette.muted)
                    if let note = command.note {
                        Text(note)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 8)
                Text(command.section)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.muted)
                if let shortcut = command.shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .padding(.leading, 5)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, command.note == nil ? 8 : 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected && command.enabled ? Palette.wash : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!command.enabled)
    }

    private func moveSelection(_ amount: Int) {
        hoveredCommandID = nil
        let enabled = matches.indices.filter { matches[$0].enabled }
        guard !enabled.isEmpty else { selected = 0; return }
        let current = enabled.firstIndex(of: selected) ?? (amount > 0 ? -1 : 0)
        selected = enabled[(current + amount + enabled.count) % enabled.count]
    }

    private func runSelected() {
        guard matches.indices.contains(selected) else { return }
        run(matches[selected])
    }

    private func run(_ command: PaletteCommand) {
        guard command.enabled else { return }
        browser.commandPalette = false
        command.action()
    }
}

private struct PaletteCommand: Identifiable {
    let title: String
    let section: String
    let shortcut: String?
    let note: String?
    let keywords: String
    let enabled: Bool
    let action: () -> Void

    var id: String { title }

    init(
        _ title: String,
        section: String,
        shortcut: String? = nil,
        note: String? = nil,
        keywords: String = "",
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.section = section
        self.shortcut = shortcut
        self.note = note
        self.keywords = keywords
        self.enabled = enabled
        self.action = action
    }

    func matches(_ word: String) -> Bool {
        let source = "\(title) \(section) \(keywords) \(note ?? "")"
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return source.contains(word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current))
    }
}
