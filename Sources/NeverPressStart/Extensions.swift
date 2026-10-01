import AppKit
import SwiftUI

/// Optional content shown on the break overlay below the title, toggled in Settings > Extensions.
/// State lives in the extension, never in its views, so every display stays in sync and
/// screen-change rebuilds keep it.
@MainActor
protocol OverlayExtension: AnyObject {
    var storage: ExtensionStorage { get }
    var title: String { get }
    var summary: String { get }
    /// Extra controls under the toggle in Settings > Extensions.
    var settingsView: AnyView? { get }
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
    var settingsView: AnyView? { nil }
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

/// White overlay text, word-wrapped and capped at 12 lines so it can't push the buttons off screen.
@MainActor
func overlayLabel() -> NSTextField {
    let label = NSTextField(wrappingLabelWithString: "")
    label.font = .systemFont(ofSize: 26, weight: .regular)
    label.textColor = NSColor.white.withAlphaComponent(0.9)
    label.alignment = .center
    label.preferredMaxLayoutWidth = 800
    label.maximumNumberOfLines = 12   // ~372 px; fits 1440x900 with every extension on
    label.cell?.truncatesLastVisibleLine = true   // ellipsis on the last line only; keeps word wrapping
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
    private var fetchTask: Task<Void, Never>?
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
        fetchTask = Task { [weak self, storage] in
            guard let joke = await Self.fetch(), !Task.isCancelled else { return }
            storage.set(joke, "cached")
            self?.text = joke
        }
    }

    func overlayDidHide() {
        fetchTask?.cancel()
        fetchTask = nil
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

    /// The trimmed body of a 2xx response, or nil if it's an error or empty.
    nonisolated static func joke(from data: Data, status: Int) -> String? {
        guard (200..<300).contains(status) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// A drop to click for each glass of water, filling towards a daily goal. Resets each local calendar day.
final class DrinkWater: OverlayExtension {
    let storage: ExtensionStorage
    let title = "Drink water"
    let summary = "Click the drop on the break screen each time you drink a glass of water."

    private let now: () -> Date
    private let calendar: Calendar
    private let rows = NSHashTable<WaterRow>.weakObjects()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         calendar: Calendar = .autoupdatingCurrent) {
        storage = ExtensionStorage(id: "drinkWater", defaults: defaults)
        self.now = now
        self.calendar = calendar
    }

    /// Glasses logged today; 0 once the stored day has passed.
    var count: Int { Self.count(storedDay: storage.string("day"), storedCount: storage.integer("count"), today: today) }

    static let defaultGoal = 8
    static let goalRange = 1...20

    var goal: Int { Self.goal(stored: storage.defaults.object(forKey: storage.key("goal")) as? Int) }

    var settingsView: AnyView? {
        AnyView(NumberRow("Daily goal", key: storage.key("goal"), default: Self.defaultGoal, range: Self.goalRange,
                          unit: "glasses"))
    }

    func addGlass() {
        let next = count + 1
        storage.set(today, "day")
        storage.set(next, "count")
        rows.allObjects.forEach(update)
    }

    func makeOverlayView() -> NSView {
        let row = WaterRow { [weak self] in self?.addGlass() }
        rows.add(row)
        update(row)
        return row
    }

    private var today: String { Self.day(for: now(), calendar: calendar) }

    private func update(_ row: WaterRow) {
        let (count, goal) = (count, goal)
        row.show(progress: Self.progress(count: count, goal: goal), fill: Self.fill(count: count, goal: goal))
    }

    static func progress(count: Int, goal: Int) -> String { "\(count) of \(goal) glasses" }

    /// Share of the goal reached, 0...1.
    static func fill(count: Int, goal: Int) -> Double { min(max(Double(count) / Double(max(goal, 1)), 0), 1) }

    /// The stored goal clamped to `goalRange`, or `defaultGoal` if unset.
    static func goal(stored: Int?) -> Int {
        min(max(stored ?? defaultGoal, goalRange.lowerBound), goalRange.upperBound)
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

/// Round glass button with a drop that fills from the bottom, beside today's count.
@MainActor
private final class WaterRow: NSStackView {
    private let button: ClosureButton
    private let countLabel = NSTextField(labelWithString: "")

    init(onClick: @escaping () -> Void) {
        button = ClosureButton(action: onClick)
        super.init(frame: .zero)
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.tintProminence = .none
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("Log a glass of water")
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 72),
            button.heightAnchor.constraint(equalToConstant: 72),
        ])

        countLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        countLabel.textColor = .white
        let hint = NSTextField(labelWithString: "Click the drop after each glass")
        hint.font = .systemFont(ofSize: 17, weight: .regular)
        hint.textColor = NSColor.white.withAlphaComponent(0.6)
        for label in [countLabel, hint] {
            label.isSelectable = false
            label.isEditable = false
        }
        let text = NSStackView(views: [countLabel, hint])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4

        setViews([button, text], in: .leading)
        spacing = 20
        alignment = .centerY
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(progress: String, fill: Double) {
        countLabel.stringValue = progress
        button.setAccessibilityValue(progress)
        button.image = Self.drop(fill: fill)
    }

    /// A grey drop with the bottom `fill` share drawn in cyan. drop.fill has no variable-value draw mode.
    private static func drop(fill: Double) -> NSImage {
        let symbol = NSImage(systemSymbolName: "drop.fill", accessibilityDescription: nil)!
        func tinted(_ color: NSColor) -> NSImage {
            symbol.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
                .applying(.init(paletteColors: [color])))!
        }
        let (empty, full) = (tinted(NSColor.white.withAlphaComponent(0.5)), tinted(.systemCyan))
        return NSImage(size: full.size, flipped: false) { rect in
            empty.draw(in: rect)
            NSBezierPath.clip(NSRect(x: 0, y: 0, width: rect.width, height: rect.height * fill))
            full.draw(in: rect)
            return true
        }
    }
}
