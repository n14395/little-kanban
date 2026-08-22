import Foundation
import OSLog

/// Asks GitHub whether there is a newer release than the one running, and does
/// nothing else.
///
/// `build.sh --publish` tags the repository and attaches a notarized `.dmg` to a
/// GitHub release. That is a real distribution channel with a real hole in it:
/// an installed copy has no way to learn a newer one exists, and the answer is
/// either Sparkle with an appcast or a button that reads the releases API. This
/// is the second, because the first is a framework, a signing key, an appcast to
/// publish and an auto-updater to be trusted with — for one unsigned `GET` of
/// public JSON, none of that is earned.
///
/// **It never runs on its own.** There is no timer, no check on launch and no
/// check when the About panel opens; the only thing that starts one is somebody
/// pressing the button. The request carries no identifier, no board and no
/// version history — only the `User-Agent` GitHub's API requires — and the
/// result is a version string and a link the user follows themselves. Nothing
/// is downloaded, and nothing installs itself.
@MainActor
@Observable
final class UpdateChecker {
    /// Where the newest release is, and what it is called.
    struct Release: Equatable, Sendable {
        var version: String
        var page: URL
        var publishedAt: Date?
    }

    enum State: Equatable {
        case idle
        case checking
        /// Nothing newer than this build is published.
        case current
        case available(Release)
        /// Something went wrong, said the way a person would say it.
        case failed(String)
    }

    private(set) var state: State = .idle

    private static let logger = Logger(
        subsystem: "com.n14395.SimpleKanban", category: "updates"
    )

    // Everything from here to `check()` is a fact about the bundle or a piece
    // of arithmetic, so none of it is the observable state's and none of it is
    // isolated. Only `check()` and `state` belong to the main actor.

    /// The version this build calls itself, from `MARKETING_VERSION` by way of
    /// the plist. Read from the bundle rather than baked in, so it cannot say
    /// one thing while the About panel says another.
    nonisolated static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    nonisolated static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    nonisolated static var copyright: String? {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
    }

    /// `owner/name`, from `SKUpdateRepository` in the plist. In the bundle
    /// rather than in code so a fork changes one line — and so `build.sh` can
    /// refuse to publish when it and the `origin` remote disagree.
    nonisolated static var repository: String? {
        let value = Bundle.main.object(forInfoDictionaryKey: "SKUpdateRepository") as? String
        return (value?.isEmpty ?? true) ? nil : value
    }

    /// Where the button sends people when there is something to fetch, and the
    /// only URL the app ever opens for this.
    nonisolated static var releasesPage: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "SKReleasesPage") as? String).flatMap(URL.init(string:))
    }

    /// The one sentence the surface shows about what pressing the button does.
    /// Here rather than in the view because it is a claim about this code.
    nonisolated static var disclosure: String {
        String(
            localized: "Checking reads the newest release tag from api.github.com. Nothing about you or your board is sent, and no check happens unless you ask for one.",
            comment: "Explains exactly what the update check does before it is used"
        )
    }

    func check() async {
        guard let repository = Self.repository,
              let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else {
            state = .failed(String(
                localized: "This build does not say where its releases are published.",
                comment: "Update check failed because the bundle has no repository in it"
            ))
            return
        }

        state = .checking
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        // GitHub refuses an API request with no User-Agent. The version is in it
        // because that is the one fact the request is *about*.
        request.setValue("SimpleKanban/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        // A stale 200 from the URL cache would report an old release as the
        // newest one, which is the single answer this must never give.
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                state = .failed(Self.message(forStatus: status))
                return
            }
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = Self.number(from: payload.tag)
            let page = URL(string: payload.page) ?? Self.releasesPage
            guard Self.isNewer(version, than: Self.currentVersion), let page else {
                state = .current
                return
            }
            state = .available(Release(
                version: version, page: page,
                publishedAt: payload.publishedAt.flatMap {
                    try? Date($0, strategy: .iso8601)
                }
            ))
        } catch is CancellationError {
            state = .idle
        } catch {
            Self.logger.error("Update check failed: \(error.localizedDescription)")
            state = .failed(String(
                localized: "The check could not be completed. \(error.localizedDescription)",
                comment: "Update check failed with a network or decoding error"
            ))
        }
    }

    /// Puts the panel back to a state that claims nothing, so a check the user
    /// has read the answer to is not still on screen a week later.
    func reset() { state = .idle }

    // MARK: Answers

    private struct Payload: Decodable {
        var tag: String
        var page: String
        var publishedAt: String?

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case page = "html_url"
            case publishedAt = "published_at"
        }
    }

    nonisolated private static func message(forStatus status: Int) -> String {
        switch status {
        case 404:
            String(localized: "No release has been published yet.",
                   comment: "Update check found no releases at all")
        case 403, 429:
            String(localized: "GitHub is rate-limiting this check. Try again in a few minutes.",
                   comment: "Update check was refused for asking too often")
        default:
            String(localized: "GitHub answered with an error (\(status)).",
                   comment: "Update check got an unexpected HTTP status")
        }
    }

    /// A tag as a version: `v1.2` and `1.2` are the same release, and anything
    /// after a dash is a pre-release suffix rather than a number.
    nonisolated static func number(from tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.hasPrefix("v") ? trimmed.dropFirst() : trimmed[...])
    }

    /// Compares dotted versions component by component, shorter one padded with
    /// zeroes — so 1.10 is newer than 1.9, which string comparison gets wrong,
    /// and 1.2 and 1.2.0 are the same release.
    ///
    /// A pre-release suffix (`1.3-beta2`) is ignored rather than ordered: this
    /// only ever has to answer "is there something newer to go and fetch", and
    /// a build that cannot parse a tag must say no rather than guess yes.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = components(of: candidate), right = components(of: current)
        guard !left.isEmpty, !right.isEmpty else { return false }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated private static func components(of version: String) -> [Int] {
        let core = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let parts = core.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return [] }
        return parts.compactMap { $0 }
    }
}
