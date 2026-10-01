import AppKit
import Foundation
import Testing
@testable import NeverPressStart

@MainActor
@Suite(.serialized)
struct ExtensionsTests {
    private let joke = OverlayExtensions.all.first { $0 is HourlyJoke }!

    @Test func extensionsAreDisabledByDefault() {
        #expect(joke.enabledKey == "extension.hourlyJoke.enabled")
        #expect(DrinkWater().enabledKey == "extension.drinkWater.enabled")
        for ext in OverlayExtensions.all {
            UserDefaults.standard.removeObject(forKey: ext.enabledKey)
            #expect(!ext.isEnabled)
            UserDefaults.standard.set(true, forKey: ext.enabledKey)
            #expect(ext.isEnabled)
            UserDefaults.standard.removeObject(forKey: ext.enabledKey)
        }
    }

    @Test func storageIsNamespaced() {
        #expect(joke.storage.key("cached") == "extension.hourlyJoke.cached")
    }

    @Test func registryHasUniqueIDs() {
        let ids = OverlayExtensions.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids == ["hourlyJoke", "drinkWater"])
    }

    @Test func jokeIsTrimmed() {
        #expect(HourlyJoke.joke(from: Data("  What am I?\n\n".utf8), status: 200) == "What am I?")
    }

    @Test func jokeViewHugsShortAndScrollsLong() {
        let view = JokeView()
        let stack = NSStackView(views: [view])   // as in the overlay
        stack.orientation = .vertical
        view.label.stringValue = "Short."
        stack.layoutSubtreeIfNeeded()
        #expect(view.frame.height == view.label.frame.height)
        view.label.stringValue = String(repeating: "A long joke line. ", count: 40)
        stack.layoutSubtreeIfNeeded()
        #expect(view.label.frame.height > view.frame.height)
    }

    @Test func emptyOrErrorResponseIsIgnored() {
        #expect(HourlyJoke.joke(from: Data(" \n".utf8), status: 200) == nil)
        #expect(HourlyJoke.joke(from: Data("Not Found".utf8), status: 404) == nil)
        #expect(HourlyJoke.joke(from: Data("joke".utf8), status: 0) == nil)
    }

    @Test func waterDayIsLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Hong_Kong")!
        let date = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13 UTC, 22:13 in Hong Kong
        #expect(DrinkWater.day(for: date, calendar: calendar) == "2026-09-21")
        #expect(DrinkWater.day(for: date + 2 * 3600, calendar: calendar) == "2026-09-22")
    }

    @Test func waterCountKeepsSameDayAndResetsOnNewDay() {
        #expect(DrinkWater.count(storedDay: "2026-09-30", storedCount: 3, today: "2026-09-30") == 3)
        #expect(DrinkWater.count(storedDay: "2026-09-29", storedCount: 3, today: "2026-09-30") == 0)
        #expect(DrinkWater.count(storedDay: nil, storedCount: 0, today: "2026-09-30") == 0)
    }

    @Test func glassesPersistAndRollOver() {
        let defaults = UserDefaults(suiteName: "ExtensionsTests.water")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.water")
        var now = Date(timeIntervalSince1970: 1_790_000_000)
        let water = DrinkWater(defaults: defaults, now: { now })
        water.addGlass()
        water.addGlass()
        #expect(DrinkWater(defaults: defaults, now: { now }).count == 2)
        #expect(defaults.integer(forKey: "extension.drinkWater.count") == 2)
        now += 86_400
        #expect(water.count == 0)
        water.addGlass()
        #expect(water.count == 1)
        defaults.removePersistentDomain(forName: "ExtensionsTests.water")
    }

    @Test func waterGoalDefaultsAndClamps() {
        #expect(DrinkWater.goal(stored: nil) == 8)
        #expect(DrinkWater.goal(stored: 5) == 5)
        #expect(DrinkWater.goal(stored: 0) == 1)
        #expect(DrinkWater.goal(stored: 99) == 20)
        let defaults = UserDefaults(suiteName: "ExtensionsTests.goal")!
        defaults.removePersistentDomain(forName: "ExtensionsTests.goal")
        let water = DrinkWater(defaults: defaults)
        #expect(water.goal == 8)
        defaults.set(12, forKey: "extension.drinkWater.goal")
        #expect(water.goal == 12)
        defaults.removePersistentDomain(forName: "ExtensionsTests.goal")
    }

    @Test func waterProgressText() {
        #expect(DrinkWater.progress(count: 1, goal: 8) == "1 of 8 glasses")
        #expect(DrinkWater.progress(count: 10, goal: 8) == "10 of 8 glasses")
        #expect(DrinkWater.fill(count: 0, goal: 8) == 0)
        #expect(DrinkWater.fill(count: 2, goal: 8) == 0.25)
        #expect(DrinkWater.fill(count: 10, goal: 8) == 1)
    }
}
