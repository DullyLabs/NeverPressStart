import AppKit

/// Optional content shown on the break overlay below the title, toggled in Settings > Extensions.
/// State lives in the extension, never in its views, so every display stays in sync and
/// screen-change rebuilds keep it.
@MainActor
protocol OverlayExtension: AnyObject {
    var storage: ExtensionStorage { get }
    var title: String { get }
    var summary: String { get }
    /// A fresh row for one overlay window. Called for every window on each show and rebuild.
    func makeOverlayView() -> NSView
    /// Once per break, before the views are made; not on screen-change rebuilds.
    func overlayWillShow()
    func overlayDidHide()
}

extension OverlayExtension {
    var id: String { storage.id }
    var enabledKey: String { storage.key("enabled") }
    var isEnabled: Bool { storage.defaults.object(forKey: enabledKey) as? Bool ?? false }
    func overlayWillShow() {}
    func overlayDidHide() {}
}

/// UserDefaults namespaced to `extension.<id>.<name>`.
struct ExtensionStorage {
    let id: String
    var defaults: UserDefaults = .standard

    func key(_ name: String) -> String { "extension.\(id).\(name)" }
    func string(_ name: String) -> String? { defaults.string(forKey: key(name)) }
    func integer(_ name: String) -> Int { defaults.integer(forKey: key(name)) }
    func set(_ value: Any?, _ name: String) { defaults.set(value, forKey: key(name)) }
}

@MainActor
enum OverlayExtensions {
    static let all: [any OverlayExtension] = [HourlyJoke(), DrinkWater()]
}

/// White overlay text, word-wrapped and capped at 4 lines so it can't push the buttons off screen.
@MainActor
func overlayLabel() -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.font = .systemFont(ofSize: 26, weight: .regular)
    label.textColor = NSColor.white.withAlphaComponent(0.9)
    label.alignment = .center
    label.preferredMaxLayoutWidth = 800
    label.maximumNumberOfLines = 4
    label.cell?.truncatesLastVisibleLine = true   // ellipsis on line 4 only; keeps word wrapping
    label.isSelectable = false
    label.isEditable = false
    return label
}

/// A joke from the author's gist, which is updated hourly. The app's only network call.
final class HourlyJoke: OverlayExtension {
    nonisolated static let url = URL(string: "https://gist.githubusercontent.com/dulangaj/136072f10b7ff4dc59645e6a81519a40/raw/joke.txt")!

    let storage = ExtensionStorage(id: "hourlyJoke")
    let title = "Hourly joke"
    let summary = "Shows a joke from the author's gist on the break screen. It's the only network call the app makes."

    private let labels = NSHashTable<NSTextField>.weakObjects()
    private var fetch: Task<Void, Never>?
    private var text: String? { didSet { labels.allObjects.forEach(apply) } }

    func makeOverlayView() -> NSView {
        let label = overlayLabel()
        labels.add(label)
        apply(to: label)
        return label
    }

    /// Shows the cached joke now, then the fresh one when the fetch returns.
    func overlayWillShow() {
        text = storage.string("cached")
        fetch = Task { [weak self, storage] in
            guard let joke = await Self.fetch(), !Task.isCancelled else { return }
            storage.set(joke, "cached")
            self?.text = joke
        }
    }

    func overlayDidHide() {
        fetch?.cancel()
        fetch = nil
    }

    private func apply(to label: NSTextField) {
        label.stringValue = text ?? ""
        label.isHidden = text == nil   // hidden views are detached from the stack, so layout is unchanged
    }

    nonisolated private static func fetch() async -> String? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let joke = joke(from: data, status: status) else {
                log("hourly joke fetch: no joke (HTTP \(status))")
                return nil
            }
            return joke
        } catch {
            log("hourly joke fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    nonisolated static let maxLength = 300

    /// The trimmed body of a 2xx response, capped at `maxLength`, or nil if it's an error or empty.
    nonisolated static func joke(from data: Data, status: Int) -> String? {
        guard (200..<300).contains(status) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(maxLength))
    }
}

/// A cup to tap for each glass of water, with today's count. Resets each local calendar day.
final class DrinkWater: OverlayExtension {
    let storage: ExtensionStorage
    let title = "Drink water"
    let summary = "Tap the cup on the break screen each time you drink a glass of water."

    private let now: () -> Date
    private let calendar: Calendar
    private let labels = NSHashTable<NSTextField>.weakObjects()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        storage = ExtensionStorage(id: "drinkWater", defaults: defaults)
        self.now = now
        self.calendar = calendar
    }

    /// Glasses logged today; 0 once the stored day has passed.
    var count: Int { Self.count(storedDay: storage.string("day"), storedCount: storage.integer("count"), today: today) }

    func addGlass() {
        let next = count + 1
        storage.set(today, "day")
        storage.set(next, "count")
        labels.allObjects.forEach(apply)
    }

    func makeOverlayView() -> NSView {
        let cup = ClosureButton { [weak self] in self?.addGlass() }
        cup.isBordered = false
        cup.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)
        cup.symbolConfiguration = .init(pointSize: 48, weight: .regular)
        cup.contentTintColor = .white
        cup.setAccessibilityLabel("Log a glass of water")

        let label = overlayLabel()
        labels.add(label)
        apply(to: label)

        let row = NSStackView(views: [cup, label])
        row.spacing = 16
        return row
    }

    private var today: String { Self.day(for: now(), calendar: calendar) }

    private func apply(to label: NSTextField) {
        let n = count
        label.stringValue = "Water today: \(n) \(n == 1 ? "glass" : "glasses")"
    }

    /// Local calendar day as yyyy-MM-dd.
    static func day(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func count(storedDay: String?, storedCount: Int, today: String) -> Int {
        storedDay == today ? storedCount : 0
    }
}
