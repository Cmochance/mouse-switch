import XCTest
@testable import MouseSwitch

final class MouseSwitchTests: XCTestCase {

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/MouseSwitchTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
    }

    private var samplePackDir: URL {
        packageRoot.appendingPathComponent("samples/CyberNeon_Windows_Pack")
    }

    func testSampleThemeImport() throws {
        XCTAssertTrue(FileManager.default.fileExists(atPath: samplePackDir.path),
                      "示例光标包目录不存在: \(samplePackDir.path)")
        let theme = try InfAndPackImporter.importDirectory(samplePackDir)
        XCTAssertEqual(theme.assignedRolesCount, 9, "应识别出 9 种光标角色")
        XCTAssertEqual(theme.animatedRolesCount, 2, "应识别出 2 个 RIFF ACON 动画光标")
    }

    func testCurParse() throws {
        let curURL = samplePackDir.appendingPathComponent("normal.cur")
        let parsed = try WinCursorParser.parse(fileURL: curURL)
        XCTAssertEqual(parsed.frameCount, 1, "静态 .cur 应只有一帧")
        XCTAssertGreaterThan(parsed.pixelWidth, 0)
        XCTAssertGreaterThan(parsed.pixelHeight, 0)
    }

    func testAniParse() throws {
        let aniURL = samplePackDir.appendingPathComponent("busy.ani")
        let parsed = try WinCursorParser.parse(fileURL: aniURL)
        XCTAssertGreaterThan(parsed.frameCount, 1, ".ani 动画光标应多于一帧")
        XCTAssertLessThanOrEqual(parsed.frameCount, WinCursorParser.maxMacOSFrames,
                                 "帧数不应超过 macOS 硬件光标 24 帧上限")
    }

    func testCapeRoundTrip() throws {
        let theme = try InfAndPackImporter.importDirectory(samplePackDir)
        let capeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MouseSwitchTests_\(UUID().uuidString).cape")
        defer { try? FileManager.default.removeItem(at: capeURL) }

        try CapeCoder.exportCape(theme: theme, to: capeURL)
        let reimported = try CapeCoder.importCape(from: capeURL)

        XCTAssertEqual(reimported.assignedRolesCount, theme.assignedRolesCount,
                       ".cape 往返后角色数量应一致")
        for role in CursorRole.allCases {
            guard let original = theme.cursor(for: role),
                  let imported = reimported.cursor(for: role) else { continue }
            XCTAssertEqual(imported.frameCount, original.frameCount,
                           "角色 \(role.rawValue) 的帧数在 .cape 往返后应一致")
        }
    }
}
