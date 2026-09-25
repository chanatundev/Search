import SwiftUI
import AppKit

/// Search's built-in actions, gathered in one place without giving them a
/// second implementation. ⌘E opens it from the menu or while a page has focus.
struct CommandPalette: View {
    @ObservedObject var browser: Browser
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var searchFocused: Bool

    private var tabCommands: [PaletteCommand] {
        let tab = browser.active
        let hasPage = tab.map { !$0.isBlank } ?? false
        return [
            .init("New Tab", section: "Tabs", shortcut: "⌘T", action: { browser.newTab() }),
            .init("New Private Tab", section: "Tabs", shortcut: "⇧⌘N", keywords: "incognito private", action: { browser.newShyTab() }),
            .init("Reopen Closed Tab", section: "Tabs", shortcut: "⇧⌘T", enabled: !browser.ghosts.isEmpty, action: { browser.reopen() }),
            .init("Close Tab", section: "Tabs", shortcut: "⌘W", enabled: tab != nil, action: { if let tab = browser.active { browser.close(tab) } }),
            .init(tab?.pin == nil ? "Pin Tab" : "Unpin Tab", section: "Tabs", keywords: "pin", enabled: hasPage, action: {
                if let tab = browser.active {
                    if tab.pin == nil { browser.pin(tab) } else { browser.unpin(tab) }
                }
            }),
            .init("Rename Tab", section: "Tabs", keywords: "name title", enabled: tab != nil, action: { if let tab = browser.active { browser.beginTabRename(tab) } }),
            .init("Duplicate Tab", section: "Tabs", shortcut: "⌘D", enabled: hasPage, action: { browser.duplicate() }),
            .init("Copy Address", section: "Tabs", shortcut: "⇧⌘C", keywords: "url link", enabled: hasPage, action: { browser.copyAddress() }),
            .init("Copy as Markdown Link", section: "Tabs", keywords: "url markdown link", enabled: hasPage, action: { browser.copyMarkdownLink() }),
            .init("Paste and Go", section: "Tabs", shortcut: "⇧⌘V", keywords: "clipboard address url", action: { browser.pasteAndGo() }),
            .init("Close Other Tabs", section: "Tabs", enabled: browser.tabs.count > 1, action: { if let tab = browser.active { browser.closeOthers(but: tab) } }),
            .init("Stop Sound in Tab", section: "Tabs", shortcut: "⇧⌘M", keywords: "mute pause audio", enabled: tab != nil, action: { browser.pauseMedia() }),
            .init("Sleep Background Tabs", section: "Tabs", note: "Current space · tabs other than the one in front", keywords: "memory inactive", action: { browser.sleepBackgroundTabs() }),
            .init("Sleep Background Spaces", section: "Tabs", note: browser.prefs.usesSpaces ? "Tabs parked in other spaces" : "Turn on Spaces in Settings first", keywords: "memory parked", enabled: browser.prefs.usesSpaces, action: { browser.sleepBackgroundSpaces() }),
        ]
    }

    private var pageCommands: [PaletteCommand] {
        let hasPage = browser.active.map { !$0.isBlank } ?? false
        return [
            .init("Reload Page", section: "Page", shortcut: "⌘R", keywords: "refresh", enabled: hasPage, action: { browser.reload() }),
            .init("Reading Mode", section: "Page", shortcut: "⇧⌘R", keywords: "reader article", enabled: hasPage, action: { browser.toggleReader() }),
            .init("Float Video", section: "Page", shortcut: "⇧⌘P", keywords: "picture in picture pip", enabled: hasPage, action: { browser.toggleFloat() }),
            .init("Hide Elements…", section: "Page", shortcut: "⇧⌘H", keywords: "remove clutter ads", enabled: hasPage, action: { browser.toggleHiding() }),
            .init("Hidden on This Site…", section: "Page", shortcut: "⇧⌘U", keywords: "restore elements", enabled: browser.hereHost != nil, action: { browser.reviewing.toggle() }),
            .init("Zoom In", section: "Page", shortcut: "⌘+", keywords: "larger", enabled: hasPage, action: { browser.zoom(by: 1.1) }),
            .init("Zoom Out", section: "Page", shortcut: "⌘-", keywords: "smaller", enabled: hasPage, action: { browser.zoom(by: 1 / 1.1) }),
            .init("Actual Size", section: "Page", shortcut: "⌘0", keywords: "reset zoom", enabled: hasPage, action: { browser.resetZoom() }),
        ]
    }

    private var developerCommands: [PaletteCommand] {
        let hasPage = browser.active.map { !$0.isBlank } ?? false
        return [
            .init("Web Inspector", section: "Developer", shortcut: "⌥⌘I", keywords: "developer tools", enabled: hasPage, action: { browser.toggleInspector() }),
            .init("JavaScript Console", section: "Developer", shortcut: "⌥⌘J", keywords: "developer tools", enabled: hasPage, action: { browser.showConsole() }),
            .init("Inspect Element", section: "Developer", shortcut: "⌥⌘C", keywords: "developer tools pick", enabled: hasPage, action: { browser.inspectElement() }),
        ]
    }

    private var windowCommands: [PaletteCommand] {
        let isFullscreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false
        return [
            .init(isFullscreen ? "Exit Full Screen" : "Enter Full Screen", section: "Window", shortcut: "⌃⌘F", keywords: "enter exit fullscreen", action: { NSApp.keyWindow?.toggleFullScreen(nil) }),
            .init("Open Settings", section: "Browser", shortcut: "⌘,", keywords: "preferences", action: { browser.tuning = true }),
            .init("Open History", section: "Browser", shortcut: "⌘Y", keywords: "recently visited", action: { browser.recalling = true }),
            .init("Open Downloads", section: "Browser", shortcut: "⇧⌘J", keywords: "download files", action: { browser.hoarding = true }),
        ]
    }

    private var commands: [PaletteCommand] { tabCommands + pageCommands + developerCommands + windowCommands }

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
        .onChange(of: query) { _, _ in selected = 0 }
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
                            row(command, selected: index == selected)
                                .id(command.id)
                                .onHover { if $0 { selected = index } }
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
