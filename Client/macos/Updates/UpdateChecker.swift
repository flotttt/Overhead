import AppKit
import Combine

// Asks GitHub for the latest release at launch and then once a day, and publishes it when it's newer than this
// app. Only reads a public URL; downloading and installing stays with the user (or Homebrew).
final class UpdateChecker: ObservableObject {
    private static let interval: TimeInterval = 24 * 60 * 60

    @Published private(set) var available: LatestRelease?

    private var timer: Timer?

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func start() {
        guard timer == nil else { return }
        check()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func openReleasePage() {
        if let url = available?.pageURL { NSWorkspace.shared.open(url) }
    }

    private func check() {
        var request = URLRequest(url: ReleaseInfo.latestURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            // A failed check (offline, rate limit) keeps what we knew; the next one tries again.
            guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200 else {
                fputs("[updates] check failed (\((response as? HTTPURLResponse)?.statusCode ?? 0))\n", stderr)
                return
            }
            let latest = ReleaseInfo.parse(json: data)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.available = ReleaseInfo.update(currentVersion: self.currentVersion, latest: latest)
                fputs("[updates] running \(self.currentVersion), latest \(latest?.tag ?? "?")\(self.available != nil ? ", update available" : "")\n", stderr)
            }
        }.resume()
    }
}
