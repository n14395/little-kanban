import Foundation
#if os(macOS)
import Security
#endif

/// Whether this build is allowed to ask CloudKit for a container.
///
/// **This is not a nicety, it is the difference between running and not.**
/// Asking `NSPersistentCloudKitContainer` for a container the process was not
/// signed for is not an error anybody can catch: `ModelContainer.init` returns
/// perfectly happily, and CoreData then traps half a second later on
/// `com.apple.coredata.cloudkit.queue`, inside
/// `-[PFCloudKitContainerProvider containerWithIdentifier:options:]`, on a
/// thread nothing this app owns. A `do`/`catch` around the open is the obvious
/// guard and it does nothing at all, because there is no `throw` — there is a
/// `SIGTRAP`.
///
/// So the entitlement is checked *before* the container is asked for, and
/// ``BoardSyncStore/app(syncing:at:)`` is the single place that asks.
///
/// The two platforms answer it differently, and neither answer is a
/// preference:
///
/// - **macOS reads its own code signature**, so the answer cannot drift from
///   what the app was actually built with. Wire a different entitlements file
///   and this changes with it, with nothing to remember.
/// - **iOS has no public API for it** — `SecTask` is macOS-only in the public
///   SDK, and the private spelling is not worth an App Store rejection — so it
///   reads a compilation condition set beside the entitlements file in
///   `project.yml`. The two are one edit in one commented block, and
///   `SyncEntitlementTests` fails the build if the flag claims a container the
///   Mac's signature does not have.
enum CloudKitEntitlement {
    /// The key a signed app carries the container list under. Same spelling on
    /// both platforms; Xcode writes it when iCloud ▸ CloudKit is ticked.
    static let key = "com.apple.developer.icloud-container-identifiers"

    /// The iCloud containers this build may open. Empty is the normal answer
    /// for a build with the plain entitlements, and for every simulator and
    /// test run.
    static var containers: [String] {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil)
        else { return [] }
        return value as? [String] ?? []
        #elseif SIMPLE_KANBAN_CLOUDKIT
        return [SyncSchema.cloudContainerID]
        #else
        return []
        #endif
    }

    static func isSigned(for container: String) -> Bool {
        containers.contains(container)
    }
}
