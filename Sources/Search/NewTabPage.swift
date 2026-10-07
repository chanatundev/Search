import AppKit
import SwiftUI
import Combine

/// What a blank tab shows: minimal search, saved bookmarks, shortcuts, or a focus clock.
enum NewTabScreen: String, CaseIterable, Identifiable {
    case minimal, bookmarks, shortcuts, focus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: return "Search"
        case .bookmarks: return "Bookmarks"
        case .shortcuts: return "Shortcuts"
        case .focus: return "Focus"
        }
    }

    var icon: String {
        switch self {
        case .minimal: return "magnifyingglass"
        case .bookmarks: return "bookmark"
        case .shortcuts: return "command"
        case .focus: return "clock"
        }
    }
}

// MARK: - Focus Header (Clock & Greeting)

struct FocusHeader: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: now))
                .font(.system(size: 54, weight: .light, design: .rounded))
                .foregroundStyle(Palette.ink)

            Text(greeting)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.muted)

            Text(Self.dateFormatter.string(from: now))
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted.opacity(0.8))
        }
        .padding(.bottom, 8)
        .onReceive(timer) { now = $0 }
    }
}

// MARK: - Bookmarks Grid

struct NewTabBookmarksView: View {
    @ObservedObject var browser: Browser

    private var bookmarks: [Bookmark] {
        func collect(_ nodes: [Bookmark]) -> [Bookmark] {
            var items: [Bookmark] = []
            for node in nodes {
                if node.url != nil {
                    items.append(node)
                }
                if let children = node.children {
                    items.append(contentsOf: collect(children))
                }
            }
            return items
        }
        return Array(collect(browser.bookmarks.roots).prefix(8))
    }

    private let columns = [
        GridItem(.adaptive(minimum: 125, maximum: 140), spacing: 12)
    ]

    var body: some View {
        if bookmarks.isEmpty {
            VStack(spacing: 6) {
                Text("No bookmarks saved yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.muted)
                Text("Press ⇧⌘B on any page to bookmark it here")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted.opacity(0.75))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Palette.wash.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(bookmarks) { item in
                    BookmarkTile(bookmark: item) {
                        if let urlString = item.url, let url = URL(string: urlString) {
                            browser.pickBookmark(url)
                        }
                    }
                }
            }
            .frame(maxWidth: 580)
            .padding(.top, 4)
        }
    }
}

private struct BookmarkTile: View {
    let bookmark: Bookmark
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            VStack(spacing: 8) {
                tileIcon
                    .frame(width: 32, height: 32)

                Text(bookmark.title.isEmpty ? (bookmark.host ?? "Site") : bookmark.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(hovering ? Palette.hover : Palette.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(hovering ? 0.06 : 0.02), radius: hovering ? 8 : 4, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }

    @ViewBuilder
    private var tileIcon: some View {
        if let site = bookmark.site, let icon = Favicons.shared.cached(site) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            let initial = String((bookmark.title.first ?? bookmark.host?.first ?? "•")).uppercased()
            ZStack {
                Circle().fill(Palette.wash)
                Text(initial)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
            }
        }
    }
}

// MARK: - Shortcuts Reference View

struct NewTabShortcutsView: View {
    @ObservedObject var browser: Browser

    private struct Item: Identifiable {
        let id = UUID()
        let key: String
        let desc: String
    }

    private let leftColumn: [Item] = [
        Item(key: "⌘T", desc: "New tab"),
        Item(key: "⌘W", desc: "Close tab"),
        Item(key: "⌃Tab", desc: "Switch tabs"),
        Item(key: "⌃`", desc: "Switch spaces"),
    ]

    private let rightColumn: [Item] = [
        Item(key: "⌘L", desc: "Address / search"),
        Item(key: "⌘K", desc: "Command palette"),
        Item(key: "⌘\\", desc: "Toggle sidebar"),
        Item(key: "⌘[ / ⌘]", desc: "Back / forward"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                column(leftColumn)
                column(rightColumn)
            }
            .padding(14)
            .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)

            Button {
                browser.tuning = true
            } label: {
                Text("Customize all shortcuts in Settings › Shortcuts")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 520)
        .padding(.top, 4)
    }

    private func column(_ items: [Item]) -> some View {
        VStack(spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Text(item.key)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.5))

                    Text(item.desc)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - New Tab Bottom Switcher Pill

struct NewTabSwitcher: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NewTabScreen.allCases) { screen in
                SwitcherButton(screen: screen, on: prefs.newTabScreen == screen) {
                    withAnimation(Motion.quick) { prefs.newTabScreen = screen }
                }
            }
        }
        .padding(3)
        .background(Palette.wash.opacity(0.85), in: Capsule())
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
    }

    private struct SwitcherButton: View {
        let screen: NewTabScreen
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 5) {
                    Image(systemName: screen.icon)
                        .font(.system(size: 10.5, weight: .medium))
                    Text(screen.title)
                        .font(.system(size: 11.5, weight: on ? .medium : .regular))
                }
                .foregroundStyle(on ? Palette.ink : (hovering ? Palette.ink.opacity(0.75) : Palette.muted))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    if on {
                        Capsule()
                            .fill(Palette.ground)
                            .shadow(color: .black.opacity(0.07), radius: 3, y: 1)
                    } else if hovering {
                        Capsule()
                            .fill(Palette.hover)
                    }
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(Motion.quick, value: hovering)
        }
    }
}
