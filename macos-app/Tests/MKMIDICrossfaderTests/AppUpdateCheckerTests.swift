import Foundation
import Testing
@testable import MKMIDICrossfader

private func releaseFixture(_ tag: String = "v0.3.1", preview: Bool = false) -> [String: Any] {
    let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    let package = "MK-Crossfader-\(version).pkg"
    return [
        "tag_name": tag,
        "html_url": "https://github.com/mks-devx/MK-Crossfader/releases/tag/\(tag)",
        "draft": false,
        "prerelease": preview,
        "assets": [package, package + ".sha256"].map { name in
            ["name": name, "state": "uploaded", "size": 90,
             "browser_download_url": "https://github.com/mks-devx/MK-Crossfader/releases/download/\(tag)/\(name)"] as [String: Any]
        },
    ]
}

@MainActor
private func fixtureChecker(_ releases: [[String: Any]], current: String = "0.3.0") -> AppUpdateChecker {
    AppUpdateChecker(currentVersion: current) { request in
        (try JSONSerialization.data(withJSONObject: releases),
         HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

@Test("Semantic versions compare numeric components and prereleases")
func semanticVersionComparison() throws {
    let current = try #require(AppSemanticVersion("0.3.0"))
    let patch = try #require(AppSemanticVersion("v0.3.1"))
    let prerelease = try #require(AppSemanticVersion("0.4.0-beta.1"))
    let release = try #require(AppSemanticVersion("0.4.0"))

    #expect(patch > current)
    #expect(prerelease > patch)
    #expect(release > prerelease)
    #expect(AppSemanticVersion("not-a-version") == nil)
}

@Test("Update checker reports a newer GitHub release")
@MainActor
func updateCheckerReportsNewRelease() async throws {
    let releaseURL = try #require(
        URL(string: "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.1")
    )
    let responseURL = try #require(
        URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases?per_page=100&page=1")
    )
    let payload = try JSONSerialization.data(withJSONObject: [releaseFixture()])

    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MK-Crossfader/0.3.0")
        #expect(request.url == responseURL)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return (
            payload,
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    await checker.checkForUpdates()

    #expect(
        checker.state == .updateAvailable(
            current: "0.3.0",
            latest: "0.3.1",
            releaseURL: releaseURL
        )
    )
}

@Test("An empty public release list has no matching installer")
@MainActor
func updateCheckerHandlesMissingRelease() async throws {
    let responseURL = try #require(
        URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases?per_page=100&page=1")
    )
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { _ in
        return (
            Data("[]".utf8),
            HTTPURLResponse(
                url: responseURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
        )
    }

    await checker.checkForUpdates()

    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}

@Test("Malformed release versions are rejected without a crash", arguments: [
    "", " ", "\n", "v", "V", "+", "v+build", "1..2", "-1.2.3", "01.2.3",
    "1.2.3+", "1.2.3++build", "1.2.3+build..1", "1.2.3+build/1",
    "1.2.3-", "1.2.3-beta..1", "1.2.3-01", "1.2.3-beta!", "1.2.3-beta 1",
    "999999999999999999999999999.0.0",
])
func malformedReleaseVersion(value: String) {
    #expect(AppSemanticVersion(value) == nil)
}

@Test("Build metadata, short versions and large prerelease numbers compare consistently")
func extendedVersionComparison() throws {
    #expect(AppSemanticVersion("v1.2.0+build.01") == AppSemanticVersion("1.2"))
    #expect(AppSemanticVersion("  V1.2.0 \n") == AppSemanticVersion("1.2.0"))
    let numeric = try #require(AppSemanticVersion("1.2.3-999999999999999999999999999"))
    let next = try #require(AppSemanticVersion("1.2.3-1000000000000000000000000000"))
    let named = try #require(AppSemanticVersion("1.2.3-beta"))
    #expect(numeric < next)
    #expect(next < named)
}

@Test("Malformed GitHub tags are never offered", arguments: ["", "v", "1.2.3-"])
@MainActor
func malformedReleaseResponse(tag: String) async throws {
    let checker = fixtureChecker([releaseFixture(tag)])
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}

@Test("Withdrawn and incomplete installers are excluded", arguments: [
    "empty", "package-only", "checksum-only", "wrong-version", "windows", "uploading", "zero-size", "draft",
])
@MainActor
func incompleteInstallers(kind: String) async {
    var release = releaseFixture("v0.2.9")
    var assets = release["assets"] as! [[String: Any]]
    switch kind {
    case "empty": assets = []
    case "package-only": assets.removeLast()
    case "checksum-only": assets.removeFirst()
    case "wrong-version": assets[0]["name"] = "MK-Crossfader-0.2.8.pkg"
    case "windows": assets[0]["name"] = "MK-Crossfader-0.2.9-windows.zip"
    case "uploading": assets[0]["state"] = "starter"
    case "zero-size": assets[0]["size"] = 0
    case "draft": release["draft"] = true
    default: Issue.record("Unknown fixture")
    }
    release["assets"] = assets
    let checker = fixtureChecker([release], current: "0.2.8")
    await checker.checkForUpdates(includePrereleases: true)
    #expect(checker.state == .noPublishedRelease(current: "0.2.8"))
    #expect(checker.state.releaseURL == nil)
}

@Test("Preview discovery requires opt-in for either GitHub flags or semantic tags", arguments: [true, false])
@MainActor
func previewOptIn(githubFlag: Bool) async {
    let tag = githubFlag ? "v0.3.1" : "v0.3.1-beta.1"
    let checker = fixtureChecker([releaseFixture(tag, preview: githubFlag)])
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
    await checker.checkForUpdates(includePrereleases: true)
    #expect(checker.state == .previewAvailable(current: "0.3.0", latest: String(tag.dropFirst()),
        releaseURL: URL(string: "https://github.com/mks-devx/MK-Crossfader/releases/tag/\(tag)")!))
    #expect(checker.state.statusText.contains("Testing prerelease"))
    #expect(checker.state.releaseURL != nil)
}

@Test("Highest eligible semantic version wins regardless of response order")
@MainActor
func versionSelection() async {
    var withdrawn = releaseFixture("v2.0.0")
    withdrawn["assets"] = []
    let checker = fixtureChecker([
        withdrawn, releaseFixture("v0.4.0", preview: true),
        releaseFixture("v0.3.2"), releaseFixture("v0.3.10"), releaseFixture("v0.3.1"),
    ])
    await checker.checkForUpdates()
    #expect(checker.state == .updateAvailable(current: "0.3.0", latest: "0.3.10",
        releaseURL: URL(string: "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.10")!))
}

@Test("Menu and settings checks share the opt-in selection without a background request")
@MainActor
func sharedPreviewSelection() async {
    var calls = 0
    let checker = AppUpdateChecker(currentVersion: "0.2.9") { request in
        calls += 1
        return (try JSONSerialization.data(withJSONObject: [releaseFixture("v0.3.0", preview: true)]),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    #expect(!checker.includeTestingPrereleases)
    checker.includeTestingPrereleases = true
    #expect(calls == 0)
    await checker.checkForUpdates()
    #expect(checker.state == .previewAvailable(current: "0.2.9", latest: "0.3.0",
        releaseURL: URL(string: "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.0")!))
    checker.includeTestingPrereleases = false
    #expect(calls == 1)
    #expect(checker.state == .idle(current: "0.2.9"))
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.2.9"))
}

@Test("An error on a later page does not offer a result from an incomplete scan")
@MainActor
func laterPageFailure() async {
    var calls = 0
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        calls += 1
        if calls > 1 { throw URLError(.networkConnectionLost) }
        return (try JSONSerialization.data(withJSONObject: Array(repeating: releaseFixture(), count: 100)),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(checker.state == .failed(current: "0.3.0"))
    #expect(checker.state.releaseURL == nil)
}

@Test("Equal or older installers never claim a local build is the latest public release", arguments: ["v0.3.0", "v0.2.9"])
@MainActor
func noDowngrades(tag: String) async {
    let checker = fixtureChecker([releaseFixture(tag)])
    await checker.checkForUpdates()
    #expect(checker.state == .upToDate(current: "0.3.0"))
    #expect(checker.state.statusText == "No newer matching installer found")
}

@Test("Release links must stay on the official repository", arguments: [
    "http://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.1",
    "https://example.com/mks-devx/MK-Crossfader/releases/tag/v0.3.1",
    "https://github.com/another/repository/releases/tag/v0.3.1",
    "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.2",
    "https://github.com:444/mks-devx/MK-Crossfader/releases/tag/v0.3.1",
    "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.1?redirect=elsewhere",
])
@MainActor
func untrustedReleaseURL(url: String) async {
    var release = releaseFixture()
    release["html_url"] = url
    let checker = fixtureChecker([release])
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}

@Test("A release URL with embedded user information is rejected")
@MainActor
func releaseURLUserInfo() async throws {
    var release = releaseFixture()
    var components = try #require(URLComponents(string: release["html_url"] as! String))
    components.user = "test-user"
    release["html_url"] = try #require(components.url).absoluteString
    let checker = fixtureChecker([release])
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}

@Test("Both installer and checksum URLs must match the official version", arguments: [0, 1])
@MainActor
func untrustedAssetURL(index: Int) async {
    var release = releaseFixture()
    var assets = release["assets"] as! [[String: Any]]
    assets[index]["browser_download_url"] = "https://example.com/download"
    release["assets"] = assets
    let checker = fixtureChecker([release])
    await checker.checkForUpdates()
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}

@Test("Release discovery follows pagination with constructed official URLs")
@MainActor
func paginatedDiscovery() async throws {
    var calls = 0
    var withdrawn = releaseFixture()
    withdrawn["assets"] = []
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        calls += 1
        #expect(request.url?.absoluteString == "https://api.github.com/repos/mks-devx/MK-Crossfader/releases?per_page=100&page=\(calls)")
        let releases = calls == 1 ? Array(repeating: withdrawn, count: 100) : [releaseFixture()]
        return (try JSONSerialization.data(withJSONObject: releases),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(calls == 2)
    #expect(checker.state.releaseURL?.lastPathComponent == "v0.3.1")
}

@Test("An incomplete bounded scan fails instead of reporting a partial result")
@MainActor
func paginationLimit() async {
    var calls = 0
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        calls += 1
        return (try JSONSerialization.data(withJSONObject: Array(repeating: releaseFixture(), count: 100)),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(calls == 10)
    #expect(checker.state == .failed(current: "0.3.0"))
}

@Test("Failed requests never imply there are no updates", arguments: [403, 404, 429, 500])
@MainActor
func requestErrors(status: Int) async {
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(checker.state == .failed(current: "0.3.0"))
}

@Test("Network errors and malformed release data remain recoverable", arguments: [true, false])
@MainActor
func invalidResponses(networkError: Bool) async {
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        if networkError { throw URLError(.timedOut) }
        return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(checker.state == .failed(current: "0.3.0"))
    checker.resetResult()
    #expect(checker.state == .idle(current: "0.3.0"))
}

@Test("Only a manual check starts a request and overlapping checks are ignored")
@MainActor
func concurrentChecks() async throws {
    var calls = 0
    var pending: CheckedContinuation<(Data, URLResponse), Error>?
    let url = URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases?per_page=100&page=1")!
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { _ in
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    #expect(calls == 0)
    let first = Task { await checker.checkForUpdates() }
    while pending == nil { await Task.yield() }
    checker.resetResult()
    #expect(checker.state.isChecking)
    await checker.checkForUpdates(includePrereleases: true)
    #expect(calls == 1)
    pending?.resume(returning: (Data("[]".utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!))
    await first.value
    #expect(checker.state == .noPublishedRelease(current: "0.3.0"))
}
