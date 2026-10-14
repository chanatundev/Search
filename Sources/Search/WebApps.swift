import AppKit
import Foundation

/// A website saved for its own Search window. Its site data stays in the
/// Space's ordinary WebKit store, so signing in works the same in both places.
struct WebApp: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var url: String

    init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url.absoluteString
    }

    var address: URL? { URL(string: url) }
}

@MainActor
enum WebApps {
    private static var file: URL { Store.file("web-apps.json") }
    private(set) static var installed: [WebApp] = read()

    private static func read() -> [WebApp] {
        guard let data = try? Data(contentsOf: Store.file("web-apps.json")),
              let apps = try? JSONDecoder().decode([WebApp].self, from: data) else { return [] }
        return apps.filter { app in
            guard let url = app.address else { return false }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
        }
    }

    @discardableResult
    static func install(url: URL, title: String) -> WebApp? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else { return nil }
        let canonical = url.absoluteString
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let app: WebApp
        if let index = installed.firstIndex(where: { $0.url == canonical }) {
            app = WebApp(id: installed[index].id, name: name.isEmpty ? (url.host() ?? "Web App") : name, url: url)
            installed[index] = app
        } else {
            app = WebApp(name: name.isEmpty ? (url.host() ?? "Web App") : name, url: url)
            installed.append(app)
        }
        save()
        return app
    }

    static func remove(_ app: WebApp) {
        installed.removeAll { $0.id == app.id }
        save()
    }

    static func open(_ app: WebApp) {
        guard let url = app.address else { return }
        let space = Browsers.front?.spaceID ?? Spaces.current
        var record = WindowRecord(space: space)
        record.webApp = app
        record.rows[space.uuidString] = Session.Shape(
            tabs: [Session.Entry(url: url.absoluteString, title: app.name)], active: 0
        )
        let browser = Browser(record: record)
        Browsers.open(browser, frame: nil)
    }

    private static func save() {
        let data = try? JSONEncoder().encode(installed)
        Disk.write(file, now: true) { data }
    }
}
