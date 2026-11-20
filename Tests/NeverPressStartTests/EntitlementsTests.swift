import Foundation
import Testing

/// The Mac App Store rejects unsandboxed uploads (error 90296), and sandboxed, the joke fetch needs network.client.
struct EntitlementsTests {
    @Test func sandboxedWithNetworkClient() throws {
        let url = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../Support/NeverPressStart.entitlements").standardized
        let plist = try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(plist["com.apple.security.network.client"] as? Bool == true)
    }
}
