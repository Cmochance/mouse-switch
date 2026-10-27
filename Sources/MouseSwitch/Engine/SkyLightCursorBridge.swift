import Foundation
import CoreGraphics
import AppKit
import ImageIO

/// Dynamically links to macOS `SkyLight.framework` private APIs to register, snapshot, and restore global system cursors.
final class SkyLightCursorBridge {
    static let shared = SkyLightCursorBridge()

    typealias CGSConnectionID = UInt32

    private typealias MainConnectionIDFunc = @convention(c) () -> CGSConnectionID

    private typealias RegisterCursorWithImagesFunc = @convention(c) (
        CGSConnectionID,
        UnsafePointer<CChar>,
        Bool,
        Bool,
        UInt,
        CFArray,
        CGSize,
        CGPoint,
        UnsafeMutablePointer<Int32>,
        CGRect,
        CGFloat,
        Int
    ) -> Int32

    private typealias RemoveRegisteredCursorFunc = @convention(c) (
        CGSConnectionID,
        UnsafePointer<CChar>,
        Bool
    ) -> Int32

    private typealias CopyRegisteredCursorImagesFunc = @convention(c) (
        CGSConnectionID,
        UnsafePointer<CChar>,
        UnsafeMutablePointer<CGSize>,
        UnsafeMutablePointer<CGPoint>,
        UnsafeMutablePointer<UInt>,
        UnsafeMutablePointer<CGFloat>,
        UnsafeMutablePointer<Unmanaged<CFArray>?>
    ) -> Int32

    private var handle: UnsafeMutableRawPointer?
    private var fnMainConnectionID: MainConnectionIDFunc?
    private var fnRegisterCursorWithImages: RegisterCursorWithImagesFunc?
    private var fnRemoveRegisteredCursor: RemoveRegisteredCursorFunc?
    private var fnCopyRegisteredCursorImages: CopyRegisteredCursorImagesFunc?

    struct SystemCursorSnapshot: Codable {
        var identifier: String
        var width: Double
        var height: Double
        var hotspotX: Double
        var hotspotY: Double
        var frameCount: Int
        var frameDuration: Double
        var representationPNGs: [Data]
    }

    private var backupFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MouseSwitch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("SystemDefaultBackup.plist")
    }

    private init() {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        if let h = dlopen(path, RTLD_LAZY) {
            self.handle = h
            if let sym = dlsym(h, "CGSMainConnectionID") {
                fnMainConnectionID = unsafeBitCast(sym, to: MainConnectionIDFunc.self)
            }
            if let sym = dlsym(h, "CGSRegisterCursorWithImages") {
                fnRegisterCursorWithImages = unsafeBitCast(sym, to: RegisterCursorWithImagesFunc.self)
            }
            if let sym = dlsym(h, "CGSRemoveRegisteredCursor") {
                fnRemoveRegisteredCursor = unsafeBitCast(sym, to: RemoveRegisteredCursorFunc.self)
            }
            if let sym = dlsym(h, "CGSCopyRegisteredCursorImages") {
                fnCopyRegisteredCursorImages = unsafeBitCast(sym, to: CopyRegisteredCursorImagesFunc.self)
            }
        }
    }

    var isAvailable: Bool {
        fnMainConnectionID != nil && fnRegisterCursorWithImages != nil
    }

    /// All cursor identifiers tracked by MouseSwitch across macOS versions
    static var allTrackedIdentifiers: [String] {
        var set = Set<String>()
        for role in CursorRole.allCases {
            for id in role.macOSIdentifiers {
                set.insert(id)
            }
        }
        for i in 1...44 {
            set.insert("com.apple.cursor.\(i)")
        }
        return Array(set).sorted()
    }

    // MARK: - System Default Cursor Backup & Restore

    /// Captures and saves the original macOS system cursor images on first run before any modification.
    func ensureSystemDefaultBackup() {
        guard !FileManager.default.fileExists(atPath: backupFileURL.path) else {
            return
        }
        guard let fnCid = fnMainConnectionID,
              let fnCopy = fnCopyRegisteredCursorImages else {
            return
        }

        let cid = fnCid()
        var snapshots: [String: SystemCursorSnapshot] = [:]

        for identifier in Self.allTrackedIdentifiers {
            var size = CGSize.zero
            var hotspot = CGPoint.zero
            var frameCount: UInt = 0
            var frameDuration: CGFloat = 0
            var unmanagedArray: Unmanaged<CFArray>?

            let err = identifier.withCString { cStr in
                fnCopy(cid, cStr, &size, &hotspot, &frameCount, &frameDuration, &unmanagedArray)
            }

            guard err == 0, let cfArr = unmanagedArray?.takeRetainedValue() else {
                continue
            }

            let count = CFArrayGetCount(cfArr)
            var repPNGs: [Data] = []
            for i in 0..<count {
                if let rawPtr = CFArrayGetValueAtIndex(cfArr, i) {
                    let cgImg = unsafeBitCast(rawPtr, to: CGImage.self)
                    if let png = ParsedCursor.encodePNG(cgImg) {
                        repPNGs.append(png)
                    }
                }
            }

            guard !repPNGs.isEmpty else { continue }

            snapshots[identifier] = SystemCursorSnapshot(
                identifier: identifier,
                width: Double(size.width),
                height: Double(size.height),
                hotspotX: Double(hotspot.x),
                hotspotY: Double(hotspot.y),
                frameCount: Int(max(1, frameCount)),
                frameDuration: Double(frameDuration),
                representationPNGs: repPNGs
            )
        }

        if !snapshots.isEmpty,
           let data = try? PropertyListEncoder().encode(snapshots) {
            try? data.write(to: backupFileURL, options: .atomic)
        }
    }

    /// Applies a `CursorTheme` globally to macOS WindowServer
    @discardableResult
    func applyTheme(_ theme: CursorTheme) -> (succeeded: Int, failed: Int) {
        ensureSystemDefaultBackup()

        guard let fnCid = fnMainConnectionID,
              let fnRegister = fnRegisterCursorWithImages else {
            return (0, 1)
        }

        // First restore defaults so roles not included in `theme` don't keep stale cursors from a previous theme
        restoreSystemDefaults(silent: true)

        let cid = fnCid()
        var succeeded = 0
        var failed = 0

        for role in CursorRole.allCases {
            guard let parsed = theme.cursor(for: role),
                  let compiled = CapeCoder.compileCursor(parsed, targetPointSize: theme.targetPointSize) else {
                continue
            }

            let size = CGSize(width: compiled.pointWidth, height: compiled.pointHeight)
            let hotspot = CGPoint(x: compiled.hotspotX, y: compiled.hotspotY)
            let bounds = CGRect(origin: .zero, size: size)
            let cfImages = compiled.representations as CFArray

            for macID in role.macOSIdentifiers {
                var seed: Int32 = 0
                let err = macID.withCString { cName in
                    fnRegister(
                        cid,
                        cName,
                        true,
                        true,
                        UInt(compiled.frameCount),
                        cfImages,
                        size,
                        hotspot,
                        &seed,
                        bounds,
                        CGFloat(compiled.frameDuration),
                        0
                    )
                }
                if err == 0 {
                    succeeded += 1
                } else {
                    failed += 1
                }
            }
        }

        return (succeeded, failed)
    }

    /// Restores the original macOS system default cursors
    @discardableResult
    func restoreSystemDefaults(silent: Bool = false) -> Bool {
        guard let fnCid = fnMainConnectionID else { return false }
        let cid = fnCid()

        var snapshots: [String: SystemCursorSnapshot] = [:]
        if let data = try? Data(contentsOf: backupFileURL),
           let decoded = try? PropertyListDecoder().decode([String: SystemCursorSnapshot].self, from: data) {
            snapshots = decoded
        }

        // 1. Re-register backed up system cursor images
        if let fnRegister = fnRegisterCursorWithImages {
            for (identifier, snap) in snapshots {
                let cgImages: [CGImage] = snap.representationPNGs.compactMap { png in
                    guard let src = CGImageSourceCreateWithData(png as CFData, nil) else { return nil }
                    return CGImageSourceCreateImageAtIndex(src, 0, nil)
                }
                guard !cgImages.isEmpty else { continue }

                let size = CGSize(width: snap.width, height: snap.height)
                let hotspot = CGPoint(x: snap.hotspotX, y: snap.hotspotY)
                let bounds = CGRect(origin: .zero, size: size)
                var seed: Int32 = 0

                _ = identifier.withCString { cName in
                    fnRegister(
                        cid,
                        cName,
                        true,
                        true,
                        UInt(max(1, snap.frameCount)),
                        cgImages as CFArray,
                        size,
                        hotspot,
                        &seed,
                        bounds,
                        CGFloat(snap.frameDuration),
                        0
                    )
                }
            }
        }

        // 2. For any tracked identifier not in the initial backup, unregister it so HIServices falls back to native PDF
        if let fnRemove = fnRemoveRegisteredCursor {
            for identifier in Self.allTrackedIdentifiers where snapshots[identifier] == nil {
                _ = identifier.withCString { cName in
                    fnRemove(cid, cName, false)
                }
            }
        }

        if !silent {
            NSCursor.arrow.set()
        }
        return true
    }
}
