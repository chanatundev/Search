import SwiftUI

/// ⌃` with spaces: a small preview of every open space, cycling through
/// them while ⌃ is held, and switching to the highlighted space when let go.
@MainActor
final class SpaceSwitcher: ObservableObject {
    @Published private(set) var candidates: [UUID] = []
    @Published private(set) var selectedID: UUID?
    @Published private(set) var visible = false
    @Published private var previews: [UUID: NSImage] = [:]

    var panelFrame: CGRect = .zero
    var cardFrames: [UUID: CGRect] = [:]
    private var rest: CGPoint?
    private var moved = false
    private var generation = UUID()

    var active: Bool { !candidates.isEmpty }

    func hover(at point: CGPoint) {
        guard visible else { return }
        if !moved {
            guard let rest else { return self.rest = point }
            guard abs(point.x - rest.x) + abs(point.y - rest.y) > 2 else { return }
            moved = true
        }
        if let id = card(at: point), id != selectedID { selectedID = id }
    }

    func card(at point: CGPoint) -> UUID? {
        cardFrames.first { $0.value.contains(point) && candidates.contains($0.key) }?.key
    }

    func step(spaces: [Space], current: UUID, backwards: Bool) {
        if candidates.isEmpty {
            candidates = spaces.map(\.id)
            guard !candidates.isEmpty else { return }
            let currentIndex = candidates.firstIndex(of: current) ?? 0
            let nextIndex = candidates.count == 1 ? 0
                : (currentIndex + (backwards ? -1 : 1) + candidates.count) % candidates.count
            selectedID = candidates[nextIndex]
            visible = true
            return
        }

        guard let selectedID, let index = candidates.firstIndex(of: selectedID) else { return }
        let next = (index + (backwards ? -1 : 1) + candidates.count) % candidates.count
        self.selectedID = candidates[next]
        visible = true
    }

    func finish(picking id: UUID? = nil) -> UUID? {
        let target = id ?? selectedID
        let valid = target.flatMap { candidates.contains($0) ? $0 : nil }
        cancel()
        return valid
    }

    func cancel() {
        guard active || visible else { return }
        generation = UUID()
        candidates = []
        selectedID = nil
        visible = false
        panelFrame = .zero
        cardFrames = [:]
        rest = nil
        moved = false
    }

    func preview(for id: UUID) -> NSImage? {
        previews[id]
    }

    func cachePreview(_ image: NSImage, for id: UUID) {
        guard candidates.contains(id) else { return }
        previews[id] = image
    }

    func capturePreviews(from browser: Browser) {
        guard visible else { return }
        let token = generation
        for space in browser.spaces {
            let activeTab: Tab? = if space.id == browser.spaceID {
                browser.active
            } else if let row = browser.parked[space.id] {
                row.tabs.first { $0.id == row.active } ?? row.tabs.first
            } else {
                nil
            }
            guard let activeTab else { continue }
            if let cached = browser.tabSwitcher.preview(for: activeTab.id, address: activeTab.address) {
                cachePreview(cached, for: space.id)
                continue
            }
            if previews[space.id] == nil {
                activeTab.preview(width: 180) { [weak self, weak activeTab] image in
                    guard let self, let activeTab, let image,
                          self.visible, self.generation == token,
                          activeTab.address == activeTab.address else { return }
                    self.cachePreview(image, for: space.id)
                }
            }
        }
    }
}

/// The overlay presenting a preview of every space.
struct SpaceSwitcherOverlay: View {
    @ObservedObject var browser: Browser
    @ObservedObject var switcher: SpaceSwitcher

    var body: some View {
        if switcher.visible {
            GeometryReader { geometry in
                let columns = min(5, max(1, switcher.candidates.count))
                let width = min(176, (geometry.size.width - 64 - CGFloat(columns - 1) * 8) / CGFloat(columns))
                let previewHeight = (width - 16) * 0.62
                let cardHeight = previewHeight + 39

                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { switcher.cancel() }

                    ZStack(alignment: .topLeading) {
                        if let selected = switcher.selectedID,
                           let index = switcher.candidates.firstIndex(of: selected) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Palette.faint)
                                .frame(width: width, height: cardHeight)
                                .offset(
                                    x: CGFloat(index % columns) * (width + 8),
                                    y: CGFloat(index / columns) * (cardHeight + 8)
                                )
                                .animation(Motion.glide, value: switcher.selectedID)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<((switcher.candidates.count + columns - 1) / columns), id: \.self) { row in
                                HStack(spacing: 8) {
                                    ForEach(Array(switcher.candidates.dropFirst(row * columns).prefix(columns)), id: \.self) { id in
                                        if let space = browser.spaces.first(where: { $0.id == id }) {
                                            card(space, width: width, previewHeight: previewHeight, height: cardHeight)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                    .background(Palette.ground, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.hairline))
                    .background(GeometryReader { box in
                        Color.clear.preference(key: PanelFrame.self, value: box.frame(in: .global))
                    })
                    .onPreferenceChange(PanelFrame.self) { frame in
                        MainActor.assumeIsolated { switcher.panelFrame = frame }
                    }
                    .onPreferenceChange(CardFrames.self) { frames in
                        MainActor.assumeIsolated { switcher.cardFrames = frames }
                    }
                    .onContinuousHover(coordinateSpace: .global) { phase in
                        if case .active(let point) = phase { switcher.hover(at: point) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .task(id: switcher.selectedID) {
                switcher.capturePreviews(from: browser)
            }
        }
    }

    private struct PanelFrame: PreferenceKey {
        static let defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue()
            if next != .zero { value = next }
        }
    }

    private struct CardFrames: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]
        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { $1 }
        }
    }

    private func previewContent(for space: Space, width: CGFloat, height: CGFloat) -> some View {
        let isCurrent = space.id == browser.spaceID
        let tabs = isCurrent ? browser.tabs : (browser.parked[space.id]?.tabs ?? [])
        let activeTab: Tab? = isCurrent ? browser.active : (browser.parked[space.id].flatMap { row in
            row.tabs.first { $0.id == row.active } ?? row.tabs.first
        })
        let color = Spaces.colours[space.colour % Spaces.colours.count]

        return ZStack {
            Palette.hover
            if let image = switcher.preview(for: space.id) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else if let activeTab, let preview = browser.tabSwitcher.preview(for: activeTab.id, address: activeTab.address) {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                VStack(spacing: 5) {
                    Image(systemName: space.symbol)
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(color)
                    if let activeTab, !activeTab.isBlank {
                        Text(activeTab.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                    } else {
                        Text(tabs.isEmpty ? "Empty" : "\(tabs.count) tab\(tabs.count == 1 ? "" : "s")")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(color.opacity(0.06))
            }
        }
        .frame(width: width, height: height)
    }

    private func card(_ space: Space, width: CGFloat, previewHeight: CGFloat, height: CGFloat) -> some View {
        let isCurrent = space.id == browser.spaceID
        let count = isCurrent ? browser.tabs.count : (browser.parked[space.id]?.tabs.count ?? 0)
        let color = Spaces.colours[space.colour % Spaces.colours.count]
        let isSelected = space.id == switcher.selectedID

        return Button { browser.commitSpaceSwitch(picking: space.id) } label: {
            VStack(spacing: 7) {
                previewContent(for: space, width: width - 16, height: previewHeight)
                    .frame(width: width - 16, height: previewHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 5))

                HStack(spacing: 6) {
                    Image(systemName: space.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                    Text(space.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(count)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(width: width, height: height, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? color.opacity(0.8) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .background(GeometryReader { box in
            Color.clear.preference(key: CardFrames.self, value: [space.id: box.frame(in: .global)])
        })
        .accessibilityLabel("Switch to space \(space.name)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }
}
