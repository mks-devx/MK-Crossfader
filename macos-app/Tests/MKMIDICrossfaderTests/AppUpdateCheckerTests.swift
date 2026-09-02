import Foundation
import Testing
@testable import MKMIDICrossfader

@Test("Semantic versions compare numeric components and prereleases")
func semanticVersionComparison() throws {
    let current = try #require(AppSemanticVersion("0.2.9"))
    let patch = try #require(AppSemanticVersion("v0.2.10"))
    let prerelease = try #require(AppSemanticVersion("0.3.0-beta.1"))
    let release = try #require(AppSemanticVersion("0.3.0"))

    #expect(patch > current)
    #expect(prerelease > patch)
    #expect(release > prerelease)
    #expect(AppSemanticVersion("not-a-version") == nil)
}

@Test("Update checker reports a newer GitHub release")
@MainActor
func updateCheckerReportsNewRelease() async throws {
    let releaseURL = try #require(
        URL(string: "https://github.com/mks-devx/MK-Crossfader/releases/tag/v0.3.0")
    )
    let responseURL = try #require(
        URL(string: "https://api.github.com/repos/mks-devx/MK-Crossfader/releases/latest")
    )
    let payload = """
    {
      "tag_name": "v0.3.0",
      "html_url": "\(releaseURL.absoluteString)"
    }
    """.data(using: .utf8)!

    let checker = AppUpdateChecker(currentVersion: "0.2.9") { request in
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "MK-Crossfader/0.2.9")
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
            current: "0.2.9",
            latest: "0.3.0",
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
    let checker = AppUpdateChecker(currentVersion: "0.2.9") { _ in
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

    #expect(checker.state == .noPublishedRelease(current: "0.2.9"))
}
