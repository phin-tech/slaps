import Foundation
import Testing
@testable import SlapsKit

@Test func versionMatchesProjectYml() throws {
    // Tests/SlapsKitTests/VersionTests.swift -> the repository
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let project = try String(contentsOf: root.appendingPathComponent("project.yml"), encoding: .utf8)
    #expect(project.contains("MARKETING_VERSION: \"\(SlapsVersion.current)\""),
            "SlapsVersion.current differs from project.yml; bump with `just bump`, which writes both")
}
