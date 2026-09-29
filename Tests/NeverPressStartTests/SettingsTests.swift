import Foundation
import Testing
@testable import NeverPressStart

/// Serialized because every test shares UserDefaults.standard.
@MainActor
@Suite(.serialized)
final class SettingsTests {
    private let keys = Setting.allCases.map(\.rawValue) + [FocusDisplay.key]
    private let defaults = UserDefaults.standard

    init() {
        for name in ["FOCUS_WORK_SECONDS", "FOCUS_SNOOZE_SECONDS", "FOCUS_IDLE_SECONDS", "FOCUS_LONG_SNOOZE_SECONDS"] {
            unsetenv(name)
        }
        keys.forEach(defaults.removeObject(forKey:))
    }

    deinit { keys.forEach(UserDefaults.standard.removeObject(forKey:)) }

    private func engineSeconds(_ setting: Setting, _ engine: PomodoroEngine) -> TimeInterval {
        switch setting {
        case .work: return engine.workSeconds
        case .snooze: return engine.snoozeSeconds
        case .idle: return engine.idleSeconds
        case .longSnooze: return engine.longSnoozeSeconds
        }
    }

    @Test(arguments: Setting.allCases)
    func storedMinutesTakeEffect(_ setting: Setting) {
        let engine = PomodoroEngine()
        #expect(setting.seconds == TimeInterval(setting.defaultMinutes * 60))
        let minutes = setting.range.lowerBound + setting.step
        defaults.set(minutes, forKey: setting.rawValue)
        #expect(setting.seconds == TimeInterval(minutes * 60))
        #expect(engineSeconds(setting, engine) == TimeInterval(minutes * 60))
    }

    @Test(arguments: Setting.allCases)
    func outOfRangeIsClamped(_ setting: Setting) {
        defaults.set(setting.range.upperBound + 1, forKey: setting.rawValue)
        #expect(setting.seconds == TimeInterval(setting.range.upperBound * 60))
        defaults.set(0, forKey: setting.rawValue)
        #expect(setting.seconds == TimeInterval(setting.range.lowerBound * 60))
    }

    @Test func newWorkPeriodUsesChangedSetting() throws {
        let engine = PomodoroEngine()
        defaults.set(7, forKey: Setting.work.rawValue)
        engine.reset()
        guard case .working(let deadline) = engine.state else { throw ExpectationFailed() }
        #expect(abs(deadline.timeIntervalSinceNow - 7 * 60) < 1)
    }

    @Test func focusDisplayDefaultsToTenCharacters() {
        #expect(FocusDisplay.displayed("Writing the article") == "Writing th")
        #expect(FocusDisplay.displayed("Article") == "Article")
    }

    @Test func focusDisplayFollowsSetting() {
        defaults.set(4, forKey: FocusDisplay.key)
        #expect(FocusDisplay.displayed("Writing the article") == "Writ")
        defaults.set(8, forKey: FocusDisplay.key)
        #expect(FocusDisplay.displayed("Writing the article") == "Writing")   // trailing space trimmed
    }

    @Test func focusDisplayLengthIsClamped() {
        defaults.set(0, forKey: FocusDisplay.key)
        #expect(FocusDisplay.length == 1)
        defaults.set(99, forKey: FocusDisplay.key)
        #expect(FocusDisplay.length == 40)
        #expect(FocusDisplay.displayed(String(repeating: "a", count: 50)).count == 40)
    }
}

private struct ExpectationFailed: Error {}
