import XCTest

final class ReturnLinksTests: XCTestCase {
    func testEveryLinkIsAnAppScheme() {
        for (bundleID, link) in ReturnLinks.byBundleID {
            let url = ReturnLinks.url(for: bundleID)
            XCTAssertNotNil(url, link)
            // A web link opens the app on its home page, not where you were.
            XCTAssertNotEqual(url?.scheme, "https", bundleID)
            XCTAssertNotEqual(url?.scheme, "http", bundleID)
        }
    }

    func testMessagesResumesTheConversation() {
        // sms:// and messages:// open a blank compose sheet.
        XCTAssertEqual(ReturnLinks.url(for: "com.apple.MobileSMS")?.absoluteString, "ichat://")
    }

    func testAppsWhoseLinkActsHaveNoLink() {
        // termius:// opens the new-host form; claude:// can start a new chat.
        XCTAssertNil(ReturnLinks.url(for: "com.crystalnix.ServerAuditor"))
        XCTAssertNil(ReturnLinks.url(for: "com.anthropic.claude"))
    }

    func testSafariAndUnknownAppsHaveNoLink() {
        XCTAssertNil(ReturnLinks.url(for: "com.apple.mobilesafari"))
        XCTAssertNil(ReturnLinks.url(for: "com.example.unknown"))
    }
}
