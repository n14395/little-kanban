import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Simple_Kanban

/// What the built bundle actually carries.
///
/// Everything here reads `Bundle.main`, which under `xcodebuild test` is the
/// app itself — the test bundle is injected into it as its host. So these are
/// not assertions about `project.yml`: they are assertions about the plist
/// XcodeGen generated, that the build copied, and that a notarisation or an App
/// Store submission would be run against. A key deleted from `project.yml`, a
/// resource that stopped being copied, and a version bumped in one place and not
/// the other all show up here and nowhere else in the suite.
@MainActor
@Suite struct PackagingTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    private func string(_ key: String) -> String? {
        (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: Identity

    @Test func theBundleIsTheAppRatherThanTheTestRunner() {
        #expect(string("CFBundleIdentifier") == "com.n14395.SimpleKanban")
        #expect(string("CFBundleName") == "Simple Kanban")
        #expect(string("CFBundleDisplayName") == "Simple Kanban")
    }

    // MARK: The extensions

    /// **Both extensions ship *inside* the app.** The system finds a widget or a
    /// share sheet in the bundle that owns it, so one that failed to embed is
    /// one nothing can ever launch — and nothing about the build says so: it
    /// compiles, it signs, and the feature is simply absent.
    @Test func theAppCarriesItsWidgetAndShareExtensions() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL, "the app has no PlugIns directory")
        let names = (try? FileManager.default.contentsOfDirectory(
            atPath: plugins.path(percentEncoded: false)
        )) ?? []
        #expect(names.contains("SimpleKanbanWidgets.appex"), "the widget extension is not embedded: \(names)")
        #expect(names.contains("SimpleKanbanShare.appex"), "the share extension is not embedded: \(names)")
    }

    /// What the share extension declares about itself, read off the built
    /// bundle rather than off `project.yml`.
    ///
    /// Each of these fails differently and none of them fails loudly. A wrong
    /// `NSExtensionPointIdentifier` is an extension the share sheet never
    /// offers; a wrong `NSExtensionPrincipalClass` — and it carries the module
    /// name, which is `PRODUCT_NAME` — is one it offers and then fails to load,
    /// with nothing in the log naming the key; an activation rule that matches
    /// nothing is an extension that is installed and never appears.
    @Test func theShareExtensionDeclaresWhatItIsAndWhatItTakes() throws {
        let plugins = try #require(Bundle.main.builtInPlugInsURL)
        let appex = try #require(
            Bundle(url: plugins.appending(path: "SimpleKanbanShare.appex")),
            "the share extension is not in the built app"
        )
        let info = appex.infoDictionary ?? [:]
        #expect(info["CFBundleIdentifier"] as? String == "com.n14395.SimpleKanban.Share")
        // The extension's version must match the app's, or a .dmg refuses to
        // install and a submission is rejected — the same rule the widgets keep.
        #expect(info["CFBundleShortVersionString"] as? String == string("CFBundleShortVersionString"))
        #expect(info["CFBundleVersion"] as? String == string("CFBundleVersion"))

        let extensionInfo = try #require(info["NSExtension"] as? [String: Any])
        #expect(extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.share-services")
        #expect(extensionInfo["NSExtensionPrincipalClass"] as? String == "SimpleKanbanShare.ShareViewController")

        let attributes = try #require(extensionInfo["NSExtensionAttributes"] as? [String: Any])
        let rule = try #require(attributes["NSExtensionActivationRule"] as? [String: Any])
        #expect(rule["NSExtensionActivationSupportsText"] as? Bool == true)
        #expect(rule["NSExtensionActivationSupportsWebURLWithMaxCount"] as? Int == 1)
    }

    // MARK: Version

    /// A marketing version the About panel can show and a build number the
    /// upgrade path can compare. Both have to be there and both have to parse:
    /// `CFBundleVersion` is compared numerically by every update mechanism there
    /// is, and one that reads "1.0-beta" compares as nothing at all.
    @Test func theBundleCarriesAVersionAndABuildNumber() throws {
        let marketing = try #require(string("CFBundleShortVersionString"))
        let build = try #require(string("CFBundleVersion"))

        let parts = marketing.split(separator: ".")
        #expect((2...3).contains(parts.count), "\(marketing) is not a marketing version")
        #expect(parts.allSatisfy { Int($0) != nil }, "\(marketing) has a non-numeric component")
        #expect(Int(build) != nil, "CFBundleVersion \(build) is not a number")
    }

    /// The version the UI shows is the version the bundle carries.
    ///
    /// A number typed into an About row is a number that goes stale on the next
    /// release and is never noticed, because nothing compares it to anything.
    /// Both accessors read the plist, so what this really asserts is that the
    /// app reads its own version rather than restating it — and it is the only
    /// test that can tell those two apart.
    @Test func theVersionTheUiShowsIsTheVersionTheBundleCarries() throws {
        let marketing = try #require(string("CFBundleShortVersionString"))
        let build = try #require(string("CFBundleVersion"))

        #expect(UpdateChecker.currentVersion == marketing)
        #expect(UpdateChecker.buildNumber == build)

        let line = AboutView.versionLine
        #expect(line.contains(marketing), "About shows \(line), the bundle says \(marketing)")
        #expect(line.contains(build), "About does not show the build number: \(line)")
    }

    /// The update check has somewhere to check. `build.sh --publish` cuts the
    /// release these two name, so a bundle that carries neither is a build with
    /// no way to learn it is out of date.
    @Test func theBundleSaysWhereItsReleasesLive() throws {
        let repository = try #require(UpdateChecker.repository,
                                      "SKUpdateRepository is missing from the built plist")
        #expect(repository.split(separator: "/").count == 2, "\(repository) is not owner/name")

        let page = try #require(UpdateChecker.releasesPage,
                                "SKReleasesPage is missing from the built plist")
        #expect(page.host() == "github.com")
        #expect(page.path().contains(repository), "the releases page is not this repository's")
    }

    /// And the comparison behind it: a build only offers an update for a
    /// version that is genuinely newer than the one in the bundle.
    @Test func theUpdateCheckComparesVersionsNumerically() {
        #expect(UpdateChecker.isNewer("1.10", than: "1.9"), "1.10 compared as a string")
        #expect(UpdateChecker.isNewer("1.2.0", than: "1.2") == false, "1.2.0 is the same release as 1.2")
        #expect(UpdateChecker.isNewer("1.0", than: UpdateChecker.currentVersion) == false,
                "this build offers itself as an update")
        #expect(UpdateChecker.number(from: "v1.4") == "1.4")
        #expect(UpdateChecker.isNewer("not-a-version", than: "1.0") == false,
                "an unparseable tag was read as newer")
    }

    // MARK: The App Store's and the notary's requirements

    /// `PrivacyInfo.xcprivacy` is required for submission and declares the
    /// required-reason APIs the app touches — `UserDefaults` for the DEBUG
    /// launch hooks and the preferences, and file timestamps for the backups
    /// folder. Absent, the submission is rejected without the binary being run.
    @Test func theBundleCarriesAPrivacyManifest() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is not in the built bundle"
        )
        let manifest = try #require(
            try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url), format: nil
            ) as? [String: Any]
        )

        #expect(manifest["NSPrivacyTracking"] as? Bool == false, "the app does not track and must say so")
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true,
                "the app collects nothing and must say so")

        let reasons = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let categories = Set(reasons.compactMap { $0["NSPrivacyAccessedAPIType"] as? String })
        #expect(categories.contains("NSPrivacyAccessedAPICategoryUserDefaults"),
                "the app reads UserDefaults and has not declared a reason")
        #expect(categories.contains("NSPrivacyAccessedAPICategoryFileTimestamp"),
                "the backups folder reads file timestamps and has not declared a reason")
        for entry in reasons {
            let codes = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
            #expect(!codes.isEmpty,
                    "\(entry["NSPrivacyAccessedAPIType"] ?? "?") is declared with no reason code")
        }
    }

    /// The macOS About panel reads `NSHumanReadableCopyright` and shows an
    /// empty line without it.
    @Test func theBundleCarriesACopyrightLine() throws {
        let copyright = try #require(string("NSHumanReadableCopyright"),
                                     "NSHumanReadableCopyright is missing from the built plist")
        #expect(copyright.contains("©") || copyright.lowercased().contains("copyright"))
        #expect(copyright.contains("20"), "the copyright line names no year: \(copyright)")
    }

    /// An empty `UILaunchScreen` is legal and gives a white flash on a dark
    /// launch. Naming a colour is the whole fix.
    @Test func theLaunchScreenIsNotABlankWhiteFlash() throws {
        #if os(iOS)
        let launch = try #require(info["UILaunchScreen"] as? [String: Any],
                                  "UILaunchScreen is missing")
        #expect(!launch.isEmpty, "UILaunchScreen is an empty dict, which is the white flash")
        #expect(launch["UIColorName"] != nil,
                "UILaunchScreen names no background colour, so it launches white")
        #endif
    }

    // MARK: What the app has already claimed

    /// The document type, the URL scheme and the drag payload types the rest of
    /// the app assumes the system knows about. An exported type the bundle does
    /// not declare is registered dynamically and conforms to nothing, which is a
    /// drag that silently does not work.
    @Test func theBundleClaimsEveryTypeTheAppUses() throws {
        let exported = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let identifiers = Set(exported.compactMap { $0["UTTypeIdentifier"] as? String })
        #expect(identifiers.contains("com.n14395.SimpleKanban.task"))
        #expect(identifiers.contains("com.n14395.SimpleKanban.subtask"))
        #expect(identifiers.contains("com.n14395.SimpleKanban.board"))

        let documents = try #require(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = documents.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] }
        #expect(contentTypes.contains("com.n14395.SimpleKanban.board"),
                "the board document is exported but not owned")

        let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains("simplekanban"), "the deep-link scheme is not claimed")

        let activities = try #require(info["NSUserActivityTypes"] as? [String])
        #expect(activities.contains("com.n14395.SimpleKanban.task"),
                "Handoff and Spotlight continuation are not claimed")
    }

    /// The drag payloads and the deep link agree with the plist rather than
    /// each having their own spelling of the same identifier. Two strings that
    /// have to match and are written in two files is one rename away from a
    /// drag that does nothing.
    @Test func theCodeAndThePlistAgreeOnEveryIdentifier() throws {
        let exported = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        let identifiers = Set(exported.compactMap { $0["UTTypeIdentifier"] as? String })
        #expect(identifiers.contains(UTType.simpleKanbanTask.identifier),
                "TaskTransfer's type is not declared in the bundle")
        #expect(identifiers.contains(UTType.simpleKanbanSubtask.identifier),
                "SubtaskTransfer's type is not declared in the bundle")

        let urlTypes = try #require(info["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        #expect(schemes.contains(TaskLink.scheme), "TaskLink's scheme is not claimed by the bundle")
    }

    /// Every slot in the app icon names an image, and every image it names is
    /// on disk.
    ///
    /// `actool` does not object to a slot with no `filename` — it fills the
    /// hole with nothing and the build succeeds — so the failure is a Dock icon
    /// that is blank at one size, or a submission rejected for a missing
    /// rendition. `Tools/make-app-icon.swift` writes the PNGs and this
    /// `Contents.json` together for exactly that reason; this is the pairing
    /// held from the other end.
    @Test func everyAppIconSlotHasItsImage() throws {
        guard SourceTree.isReachable else { return }
        let set = SourceTree.checkout
            .appending(path: "Resources/Assets.xcassets/AppIcon.appiconset")
        let manifest = try #require(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: set.appending(path: "Contents.json"))
            ) as? [String: Any]
        )
        let slots = try #require(manifest["images"] as? [[String: Any]])

        #expect(slots.count == 11, "the icon declares \(slots.count) slots")
        var named: Set<String> = []
        for slot in slots {
            let size = slot["size"] as? String ?? "?"
            let idiom = slot["idiom"] as? String ?? "?"
            let filename = try #require(slot["filename"] as? String,
                                        "the \(idiom) \(size) slot names no image")
            named.insert(filename)
            #expect(FileManager.default.fileExists(atPath: set.appending(path: filename).path(percentEncoded: false)),
                    "\(filename) is declared and not on disk")
        }

        // And nothing on disk is unreferenced: an image no slot names is a
        // rendition that silently never ships.
        let onDisk = Set(
            (try? FileManager.default.contentsOfDirectory(atPath: set.path(percentEncoded: false)))?
                .filter { $0.hasSuffix(".png") } ?? []
        )
        #expect(onDisk == named, "the folder and the manifest disagree: \(onDisk.symmetricDifference(named))")

        // Both platforms are covered: macOS draws ten renditions off this set
        // and iOS the single 1024.
        let idioms = slots.compactMap { $0["idiom"] as? String }
        #expect(idioms.count { $0 == "mac" } == 10)
        #expect(slots.contains { $0["platform"] as? String == "ios" })
    }

    /// Encryption, category and in-place opening: the three answers the
    /// submission form asks for and the build can supply.
    @Test func theBundleAnswersTheSubmissionQuestions() {
        #expect(info["ITSAppUsesNonExemptEncryption"] as? Bool == false)
        #expect(string("LSApplicationCategoryType") == "public.app-category.productivity")
        #expect(info["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)
    }
}
