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
    let appZipURL: URL?    // Overhead.zip, nil if the release doesn't have it (then only the page can be opened)
    let checksumURL: URL?  // Overhead.zip.sha256
}

// Reads GitHub's "latest release" reply and decides whether it's an update for this app.
enum ReleaseInfo {
    static let latestURL = URL(string: "https://api.github.com/repos/flotttt/Overhead/releases/latest")!
    static let appZipName = "Overhead.zip"
    // Releases also carry SonyNotch.zip (make release) for the updater of SonyNotch 1.4 and older.

    private struct Reply: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let html_url: URL
        let draft: Bool?
        let prerelease: Bool?
        let assets: [Asset]?
    }

    // nil for drafts, pre-releases and anything unreadable.
    static func parse(json: Data) -> LatestRelease? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: json),
              reply.draft != true, reply.prerelease != true,
              let version = AppVersion(reply.tag_name) else { return nil }
        let assets = reply.assets ?? []
        func asset(_ name: String) -> URL? { assets.first { $0.name == name }?.browser_download_url }
        return LatestRelease(version: version, tag: reply.tag_name, pageURL: reply.html_url,
                             appZipURL: asset(appZipName), checksumURL: asset(appZipName + ".sha256"))
    }

    // The hash in a `shasum -a 256` output ("<64 hex>  Overhead.zip"), lowercased; nil if there isn't one.
    static func checksum(fromFile text: String) -> String? {
        guard let first = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).first else { return nil }
        let hash = first.lowercased()
        guard hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) else { return nil }
        return hash
    }

    // The release, only when it's newer than the running app (whose version must be readable).
    static func update(currentVersion: String, latest: LatestRelease?) -> LatestRelease? {
        guard let latest = latest, let current = AppVersion(currentVersion), latest.version > current else { return nil }
        return latest
    }
}
