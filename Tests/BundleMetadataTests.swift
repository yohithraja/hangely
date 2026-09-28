//
//  BundleMetadataTests.swift
//  HanglyTests
//

import Foundation
import Testing

@testable import Hangly

/// `AppConstants` reads the bundle for its identity strings, with literal fallbacks
/// for the test bundle — which has no `Info.plist` of the app's. Those fallbacks are
/// the only place any of this is written twice, so this is what stops them drifting
/// from what actually ships.
@Suite("Bundle metadata")
struct BundleMetadataTests {
    /// The app's `Info.plist`, read from the repository rather than from a build.
    private func appInfoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Hangly/App/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test("The copyright the app shows is the copyright the bundle declares")
    func copyrightMatchesInfoPlist() throws {
        let declared = try #require(appInfoPlist()["NSHumanReadableCopyright"] as? String)

        #expect(declared == "Copyright © 2026. sharancreatedthis.")
        // Running outside the app bundle, this is the fallback; the point of the test
        // is that the fallback and the plist say the same thing.
        #expect(AppConstants.copyright == declared)
        #expect(!declared.localizedCaseInsensitiveContains("all rights reserved"))
    }

    @Test("Version and build come from the bundle, not from a literal in the code")
    func versionKeysAreSubstituted() throws {
        let plist = try appInfoPlist()

        // These stay build-setting substitutions so the version is stated once, in
        // project.yml, and never edited in two places.
        #expect(plist["CFBundleShortVersionString"] as? String == "$(MARKETING_VERSION)")
        #expect(plist["CFBundleVersion"] as? String == "$(CURRENT_PROJECT_VERSION)")
    }

    @Test("The bundle declares what a distributable macOS app has to")
    func requiredKeysArePresent() throws {
        let plist = try appInfoPlist()

        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["LSApplicationCategoryType"] as? String == "public.app-category.utilities")
        #expect(plist["NSPrincipalClass"] as? String == "NSApplication")
        #expect(plist["CFBundleIconName"] as? String == "AppIcon")
    }
}
