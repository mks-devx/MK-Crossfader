import Combine
import Foundation

struct AppSemanticVersion: Comparable, Equatable {
    private let components: [Int]
    private let prerelease: [String]?

    var isPrerelease: Bool { prerelease != nil }

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        let buildParts = normalized.split(
            separator: "+", maxSplits: 1, omittingEmptySubsequences: false
        )
        guard let version = buildParts.first, !version.isEmpty else { return nil }
        if buildParts.count == 2 {
            guard Self.validIdentifiers(buildParts[1], prerelease: false) else { return nil }
        }
        normalized = String(version)

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
            guard Self.isDigits(part),
                part.count == 1 || part.first != "0",
                let number = Int(part)
            else {
                return nil
            }
            parsedComponents.append(number)
        }

        if versionParts.count == 2 {
            let identifiers = versionParts[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard Self.validIdentifiers(versionParts[1], prerelease: true) else {
                return nil
            }
            prerelease = identifiers.map(String.init)
        } else {
            prerelease = nil
        }
        while parsedComponents.count > 1 && parsedComponents.last == 0 {
            parsedComponents.removeLast()
        }
        components = parsedComponents
    }

    private static func isDigits<S: StringProtocol>(_ value: S) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func validIdentifiers(_ value: Substring, prerelease: Bool) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy { part in
            !part.isEmpty && part.utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0)
                    || (97...122).contains($0) || $0 == 45
            } && (!prerelease || !isDigits(part) || part.count == 1 || part.first != "0")
        }
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

            switch (isDigits(left), isDigits(right)) {
            case (true, true):
                return left.count == right.count ? left < right : left.count < right.count
            case (true, false):
                return true
            case (false, true):
                return false
            case (false, false):
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
    case previewAvailable(current: String, latest: String, releaseURL: URL)
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
        case .upToDate:
            return "No newer matching installer found"
        case .updateAvailable(_, let latest, _):
            return "Version \(latest) is available"
        case .previewAvailable(_, let latest, _):
            return "Testing prerelease \(latest) is available"
        case .noPublishedRelease:
            return "No matching installer available"
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
        case .updateAvailable, .previewAvailable:
            return "arrow.down.circle"
        case .noPublishedRelease:
            return "shippingbox"
        case .failed:
            return "exclamationmark.triangle"
        }
    }

    var releaseURL: URL? {
        switch self {
        case .updateAvailable(_, _, let releaseURL), .previewAvailable(_, _, let releaseURL):
            return releaseURL
        default:
            return nil
        }
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    static let releasesPageURL = URL(
        string: "https://github.com/mks-devx/MK-Crossfader/releases"
    )!

    @Published private(set) var state: AppUpdateState
    @Published var includeTestingPrereleases = false {
        didSet { resetResult() }
    }

    let currentVersion: String

    private let releasesAPIURL = URL(
        string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases"
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

    func resetResult() {
        guard !state.isChecking else { return }
        state = .idle(current: currentVersion)
    }

    func checkForUpdates(includePrereleases: Bool? = nil) async {
        guard !state.isChecking else {
            return
        }
        state = .checking(current: currentVersion)
        let includePrereleases = includePrereleases ?? includeTestingPrereleases

        do {
            guard let current = AppSemanticVersion(currentVersion) else {
                throw URLError(.cannotParseResponse)
            }
            var candidate: (release: GitHubRelease, version: AppSemanticVersion)?
            // Release creation order is not version order. Check all bounded pages,
            // rather than treating the first (possibly withdrawn) release as latest.
            for page in 1...10 {
                var components = URLComponents(url: releasesAPIURL, resolvingAgainstBaseURL: false)!
                components.queryItems = [URLQueryItem(name: "per_page", value: "100"),
                                         URLQueryItem(name: "page", value: String(page))]
                let url = components.url!
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
                request.timeoutInterval = 10
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
                request.setValue("MK-Crossfader/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await dataLoader(request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse,
                    response.url == url, response.statusCode == 200
                else {
                    throw URLError(.badServerResponse)
                }
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                for release in releases {
                    guard let version = release.installableVersion,
                        includePrereleases || !release.isPreview
                    else { continue }
                    if let existing = candidate {
                        guard existing.version < version
                            || (existing.version == version && existing.release.isPreview && !release.isPreview)
                        else { continue }
                    }
                    candidate = (release, version)
                }
                if releases.count < 100 { break }
                guard page < 10 else { throw URLError(.dataLengthExceedsMaximum) }
            }
            guard let candidate else {
                state = .noPublishedRelease(current: currentVersion)
                return
            }
            let release = candidate.release
            if candidate.version > current {
                state = release.isPreview
                    ? .previewAvailable(current: currentVersion, latest: release.displayVersion, releaseURL: release.htmlURL)
                    : .updateAvailable(current: currentVersion, latest: release.displayVersion, releaseURL: release.htmlURL)
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
        ) as? String ?? "0.3.1"
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    var displayVersion: String {
        tagName.first == "v" || tagName.first == "V" ? String(tagName.dropFirst()) : tagName
    }

    var isPreview: Bool {
        prerelease || AppSemanticVersion(tagName)?.isPrerelease == true
    }

    var installableVersion: AppSemanticVersion? {
        guard !draft, tagName == tagName.trimmingCharacters(in: .whitespacesAndNewlines),
            let version = AppSemanticVersion(tagName),
            Self.isOfficialURL(htmlURL, path: "/mks-devx/MK-Crossfader/releases/tag/\(tagName)")
        else { return nil }
        let package = "MK-Crossfader-\(displayVersion).pkg"
        for name in [package, package + ".sha256"] {
            guard assets.contains(where: {
                $0.name == name && $0.state == "uploaded" && $0.size > 0
                    && Self.isOfficialURL($0.browserDownloadURL,
                        path: "/mks-devx/MK-Crossfader/releases/download/\(tagName)/\(name)")
            }) else { return nil }
        }
        return version
    }

    private static func isOfficialURL(_ url: URL, path: String) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && (url.port == nil || url.port == 443)
            && url.user == nil && url.password == nil
            && url.query == nil && url.fragment == nil && url.path == path
    }

    struct Asset: Decodable {
        let name: String
        let state: String
        let size: Int
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, state, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft, prerelease, assets
    }
}
