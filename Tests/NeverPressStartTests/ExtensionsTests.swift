import Foundation
import Testing
@testable import NeverPressStart

@Suite(.serialized)
struct ExtensionsTests {
    private let joke = HourlyJoke()

    @Test func hourlyJokeIsDisabledByDefault() {
        UserDefaults.standard.removeObject(forKey: joke.enabledKey)
        #expect(joke.enabledKey == "extension.hourlyJoke.enabled")
        #expect(!joke.isEnabled)
        UserDefaults.standard.set(true, forKey: joke.enabledKey)
        #expect(joke.isEnabled)
        UserDefaults.standard.removeObject(forKey: joke.enabledKey)
    }

    @Test func registryHasUniqueIDs() {
        let ids = OverlayExtensions.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(joke.id))
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
}
