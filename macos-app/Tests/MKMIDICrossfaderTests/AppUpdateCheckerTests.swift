import Foundation
import Testing
@testable import MKMIDICrossfader

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
        URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases/latest")
    )
    let payload = """
    {
      "tag_name": "v0.3.1",
      "html_url": "\(releaseURL.absoluteString)"
    }
    """.data(using: .utf8)!

    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MK-Crossfader/0.3.0")
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

@Test("Update checker handles a repository without public releases")
@MainActor
func updateCheckerHandlesMissingRelease() async throws {
    let responseURL = try #require(
        URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases/latest")
    )
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { _ in
        return (
            Data(),
            HTTPURLResponse(
                url: responseURL,
                statusCode: 404,
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

@Test("A malformed GitHub tag produces a recoverable update error", arguments: ["", "v", "1.2.3-"])
@MainActor
func malformedReleaseResponse(tag: String) async throws {
    let checker = AppUpdateChecker(currentVersion: "0.3.0") { request in
        let payload = try JSONSerialization.data(withJSONObject: [
            "tag_name": tag,
            "html_url": "https://github.com/mks-devx/MK-Crossfader/releases",
        ])
        return (payload, HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!)
    }
    await checker.checkForUpdates()
    #expect(checker.state == .failed(current: "0.3.0"))
}
