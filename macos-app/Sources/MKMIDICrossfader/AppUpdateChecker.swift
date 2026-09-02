import Combine
import Foundation

struct AppSemanticVersion: Comparable, Equatable {
    private let components: [Int]
    private let prerelease: [String]?

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(separator: "+", maxSplits: 1)[0])

        let versionParts = normalized.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let numberParts = versionParts[0].split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard !numberParts.isEmpty else {
            return nil
        }

        var parsedComponents: [Int] = []
        for part in numberParts {
            guard !part.isEmpty, let number = Int(part), number >= 0 else {
                return nil
            }
            parsedComponents.append(number)
        }

        if versionParts.count == 2 {
            let identifiers = versionParts[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else {
                return nil
            }
            prerelease = identifiers.map(String.init)
        } else {
            prerelease = nil
        }
        components = parsedComponents
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (.some(left), .some(right)):
            return prerelease(left, isLowerThan: right)
        }
    }

    private static func prerelease(
        _ lhs: [String],
        isLowerThan rhs: [String]
    ) -> Bool {
        for index in 0..<min(lhs.count, rhs.count) {
            let left = lhs[index]
            let right = rhs[index]
            if left == right {
                continue
            }

            switch (Int(left), Int(right)) {
            case let (.some(leftNumber), .some(rightNumber)):
                return leftNumber < rightNumber
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return left < right
            }
        }
        return lhs.count < rhs.count
    }
}

enum AppUpdateState: Equatable {
    case idle(current: String)
    case checking(current: String)
    case upToDate(current: String)
    case updateAvailable(current: String, latest: String, releaseURL: URL)
    case noPublishedRelease(current: String)
    case failed(current: String)

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }

    var statusText: String {
        switch self {
        case .idle(let current):
            return "Version \(current)"
        case .checking:
            return "Checking GitHub..."
        case .upToDate(let current):
            return "Version \(current) is up to date"
        case .updateAvailable(_, let latest, _):
            return "Version \(latest) is available"
        case .noPublishedRelease:
            return "No public release is available yet"
        case .failed:
            return "Could not check GitHub"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "info.circle"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .upToDate:
            return "checkmark.circle"
        case .updateAvailable:
            return "arrow.down.circle"
        case .noPublishedRelease:
            return "shippingbox"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var releaseURL: URL? {
        if case .updateAvailable(_, _, let releaseURL) = self {
            return releaseURL
        }
        return nil
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    static let releasesPageURL = URL(
        string: "https://github.com/mks-devx/MK-Crossfader/releases"
    )!

    @Published private(set) var state: AppUpdateState

    let currentVersion: String

    private let latestReleaseURL = URL(
        string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases/latest"
    )!
    private let dataLoader: DataLoader

    init(
        currentVersion: String? = nil,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        let resolvedVersion = currentVersion ?? Self.bundledVersion
        self.currentVersion = resolvedVersion
        self.dataLoader = dataLoader
        state = .idle(current: resolvedVersion)
    }

    func checkForUpdates() async {
        guard !state.isChecking else {
            return
        }
        state = .checking(current: currentVersion)

        var request = URLRequest(url: latestReleaseURL)
        request.timeoutInterval = 10
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "2026-03-10",
            forHTTPHeaderField: "X-GitHub-Api-Version"
        )
        request.setValue(
            "MK-Crossfader/\(currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await dataLoader(request)
            guard let response = response as? HTTPURLResponse else {
                state = .failed(current: currentVersion)
                return
            }

            if response.statusCode == 404 {
                state = .noPublishedRelease(current: currentVersion)
                return
            }
            guard response.statusCode == 200 else {
                state = .failed(current: currentVersion)
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard
                let current = AppSemanticVersion(currentVersion),
                let latest = AppSemanticVersion(release.tagName)
            else {
                state = .failed(current: currentVersion)
                return
            }

            let latestDisplayVersion = Self.displayVersion(release.tagName)
            if latest > current {
                state = .updateAvailable(
                    current: currentVersion,
                    latest: latestDisplayVersion,
                    releaseURL: release.htmlURL
                )
            } else {
                state = .upToDate(current: currentVersion)
            }
        } catch {
            state = .failed(current: currentVersion)
        }
    }

    private static var bundledVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0.2.8"
    }

    private static func displayVersion(_ value: String) -> String {
        guard value.first == "v" || value.first == "V" else {
            return value
        }
        return String(value.dropFirst())
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
