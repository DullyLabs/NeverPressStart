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

    @Test func jokeIsCapped() {
        let long = String(repeating: "a", count: HourlyJoke.maxLength + 50)
        #expect(HourlyJoke.joke(from: Data(long.utf8), status: 200)?.count == HourlyJoke.maxLength)
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
}
