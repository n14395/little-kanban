import Foundation
import SwiftData
import Testing
#if os(macOS)
import Security
#endif
@testable import LittleKanban

/// The one rule that stands between this app and a launch that lasts half a
/// second: **never name a CloudKit container this build was not signed for.**
///
/// The defect these pin was not a bug in the sync code. `BoardSyncStore` asked
/// for `iCloud.com.n14395.LittleKanban` on a build carrying the plain
/// entitlements, wrapped in a `do`/`catch` that could never fire, because
/// `ModelContainer.init` succeeds and CoreData then traps on
/// `com.apple.coredata.cloudkit.queue` inside
/// `-[PFCloudKitContainerProvider containerWithIdentifier:options:]`. A trap on
/// a queue nothing here owns is not catchable, is not testable after the fact,
/// and killed every launch after the first.
///
/// So the decision is made *before* the ask, by
/// ``BoardSyncStore/cloudContainer(syncing:isRunningTests:signedContainers:)``,
/// and that function is pure so this suite can put it through every combination
/// without opening anything.
@MainActor
@Suite struct SyncEntitlementTests {
    private static let ours = SyncSchema.cloudContainerID

    // MARK: The decision

    @Test func aBuildSignedForTheContainerAsksForIt() {
        #expect(BoardSyncStore.cloudContainer(
            syncing: true, isRunningTests: false, signedContainers: [Self.ours]
        ) == Self.ours)
    }

    /// The regression. A build with the plain entitlements is signed for no
    /// containers at all, and asking anyway is the crash.
    @Test func aBuildSignedForNothingStaysLocal() {
        #expect(BoardSyncStore.cloudContainer(
            syncing: true, isRunningTests: false, signedContainers: []
        ) == nil)
    }

    /// Signed for *a* container is not signed for *ours*. `isEmpty` would have
    /// let this through, and CloudKit traps on the mismatch just as hard as on
    /// the absence.
    @Test func aBuildSignedForSomebodyElsesContainerStaysLocal() {
        #expect(BoardSyncStore.cloudContainer(
            syncing: true, isRunningTests: false,
            signedContainers: ["iCloud.com.example.SomethingElse"]
        ) == nil)
    }

    @Test func syncSwitchedOffStaysLocalEvenWhenSigned() {
        #expect(BoardSyncStore.cloudContainer(
            syncing: false, isRunningTests: false, signedContainers: [Self.ours]
        ) == nil)
    }

    /// The suite runs as the app's own test host under the app's own bundle
    /// identifier, so an entitled build would hand the fixtures to whatever
    /// iCloud account the machine is signed in to — and then to every device on
    /// it.
    @Test func aTestRunStaysLocalEvenWhenSignedAndSwitchedOn() {
        #expect(BoardSyncStore.cloudContainer(
            syncing: true, isRunningTests: true, signedContainers: [Self.ours]
        ) == nil)
    }

    // MARK: What the app actually opens

    /// The end of the rope: whatever the preference says, the container this
    /// build opens must not name a CloudKit database. `cloudKitContainerIdentifier`
    /// is the property CoreData reads on its way to the trap.
    @Test func theStoreTheAppOpensNamesNoCloudKitContainer() throws {
        let url = URL.temporaryDirectory
            .appending(path: "SyncEntitlementTests-\(UUID().uuidString)/board.store")
        let store = try BoardSyncStore.app(syncing: true, at: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        #expect(store.isSyncing == false)
        for configuration in store.container.configurations {
            #expect(configuration.cloudKitContainerIdentifier == nil,
                    "the suite opened a store pointed at \(configuration.cloudKitContainerIdentifier ?? "")")
        }
    }

    /// The switch in the settings screen reads this, and so does `isOn`. A
    /// preference cannot turn on something the signature does not allow.
    @Test func thePreferenceCannotOutvoteTheSignature() {
        #expect(SyncPreference.isAvailable == CloudKitEntitlement.isSigned(for: Self.ours))
        if !SyncPreference.isAvailable {
            #expect(SyncPreference.isOn == false)
        }
    }

    // MARK: Reading the entitlement

    /// Whatever the reader returns, it returns container identifiers — not a
    /// stray string, and not an unlabelled truthy value read from the wrong key.
    @Test func theContainersItReportsLookLikeContainers() {
        for container in CloudKitEntitlement.containers {
            #expect(container.hasPrefix("iCloud."),
                    "\(container) is not an iCloud container identifier")
        }
    }

    @Test func theEntitlementKeyIsTheOneXcodeWrites() {
        #expect(CloudKitEntitlement.key == "com.apple.developer.icloud-container-identifiers")
    }

    #if os(macOS)
    /// Two different frameworks, one fact. `SecTask` asks the kernel what this
    /// process was granted; `SecCode` reads the signature off the bundle on
    /// disk. If the reader ever picked up something other than the real
    /// entitlement — a cached value, the wrong key, a stale process — these two
    /// would part company.
    @Test func theSignatureAgreesWithItself() throws {
        var code: SecCode?
        try #require(SecCodeCopySelf([], &code) == errSecSuccess)
        var onDisk: SecStaticCode?
        try #require(SecCodeCopyStaticCode(try #require(code), [], &onDisk) == errSecSuccess)

        var information: CFDictionary?
        try #require(SecCodeCopySigningInformation(
            try #require(onDisk), SecCSFlags(rawValue: kSecCSSigningInformation), &information
        ) == errSecSuccess)

        let signed = information as? [String: Any]
        let entitlements = signed?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        let fromSignature = entitlements?[CloudKitEntitlement.key] as? [String] ?? []
        #expect(Set(fromSignature) == Set(CloudKitEntitlement.containers))
    }
    #endif
}
