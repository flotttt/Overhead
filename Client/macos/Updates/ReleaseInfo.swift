import Foundation

// A "1.2.3" version, compared number by number. A leading "v" and a pre-release suffix ("-beta.1") are ignored,
// missing numbers count as 0. Pure, tested in LogicTests.
struct AppVersion: Comparable {
    let numbers: [Int]

    init?(_ text: String) {
        var core = text.trimmingCharacters(in: .whitespaces)
        if core.hasPrefix("v") || core.hasPrefix("V") { core.removeFirst() }
        if let dash = core.firstIndex(of: "-") { core = String(core[..<dash]) }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        numbers = parts.compactMap { $0 }
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs) == rhs.padded(to: lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.padded(to: rhs).lexicographicallyPrecedes(rhs.padded(to: lhs))
    }

    private func padded(to other: AppVersion) -> [Int] {
        numbers + Array(repeating: 0, count: max(0, other.numbers.count - numbers.count))
    }
}

// The latest published release on GitHub.
struct LatestRelease: Equatable {
    let version: AppVersion
    let tag: String
    let pageURL: URL
}

// Reads GitHub's "latest release" reply and decides whether it's an update for this app.
enum ReleaseInfo {
    static let latestURL = URL(string: "https://api.github.com/repos/flotttt/SonyNotch/releases/latest")!

    private struct Reply: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
    }

    // nil for drafts, pre-releases and anything unreadable.
    static func parse(json: Data) -> LatestRelease? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: json),
              reply.draft != true, reply.prerelease != true,
              let version = AppVersion(reply.tag_name) else { return nil }
        return LatestRelease(version: version, tag: reply.tag_name, pageURL: reply.html_url)
    }

    // The release, only when it's newer than the running app (whose version must be readable).
    static func update(currentVersion: String, latest: LatestRelease?) -> LatestRelease? {
        guard let latest = latest, let current = AppVersion(currentVersion), latest.version > current else { return nil }
        return latest
    }
}
