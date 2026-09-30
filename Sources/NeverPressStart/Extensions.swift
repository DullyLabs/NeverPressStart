import Foundation

/// Optional content shown on the break overlay below the title, toggled in Settings > Extensions.
protocol OverlayExtension: Sendable {
    var id: String { get }
    var title: String { get }
    var summary: String { get }
    /// Shown instantly when the overlay appears, before `fetch()` returns.
    var cachedText: String? { get }
    /// Fresh text, or nil to keep showing `cachedText`.
    func fetch() async -> String?
}

extension OverlayExtension {
    var enabledKey: String { "extension.\(id).enabled" }
    var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
}

enum OverlayExtensions {
    static let all: [any OverlayExtension] = [HourlyJoke()]
}

/// A joke from the user's gist, which is updated hourly. The app's only network call.
struct HourlyJoke: OverlayExtension {
    static let url = URL(string: "https://gist.githubusercontent.com/dulangaj/136072f10b7ff4dc59645e6a81519a40/raw/joke.txt")!
    static let cacheKey = "extension.hourlyJoke.cached"

    let id = "hourlyJoke"
    let title = "Hourly joke"
    let summary = "Shows a joke from your gist on the break screen. It's the only network call the app makes."

    var cachedText: String? { UserDefaults.standard.string(forKey: Self.cacheKey) }

    func fetch() async -> String? {
        let request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let joke = Self.joke(from: data, status: status) else {
                log("hourly joke fetch: no joke (HTTP \(status))")
                return nil
            }
            UserDefaults.standard.set(joke, forKey: Self.cacheKey)
            return joke
        } catch {
            log("hourly joke fetch failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// The trimmed body of a 2xx response, or nil if it's an error or empty.
    static func joke(from data: Data, status: Int) -> String? {
        guard (200..<300).contains(status) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
