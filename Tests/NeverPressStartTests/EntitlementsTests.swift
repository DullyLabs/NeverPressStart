import Foundation
import Testing

/// The Mac App Store rejects unsandboxed uploads (error 90296), so only its variant is sandboxed; sandboxed, the joke fetch needs network.client.
struct EntitlementsTests {
    private func entitlements(_ name: String) throws -> [String: Any] {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Support/\(name).entitlements").standardized
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    }

    @Test func appStoreVariantSandboxedWithNetworkClient() throws {
        let plist = try entitlements("NeverPressStart-AppStore")
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.network.client"] as? Bool == true)
        #expect(plist["com.apple.security.personal-information.calendars"] as? Bool == true)
    }

    @Test func defaultAppNotSandboxed() throws {
        #expect(try entitlements("NeverPressStart")["com.apple.security.app-sandbox"] == nil)
    }
}
