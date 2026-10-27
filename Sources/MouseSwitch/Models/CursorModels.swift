import Foundation
import CoreGraphics
import AppKit

/// Standard cursor roles bridging Windows cursor types and macOS CoreGraphics identifiers.
public enum CursorRole: String, CaseIterable, Codable, Identifiable {
    case arrow = "Arrow"
    case ibeam = "IBeam"
    case hand = "Hand"
    case wait = "Wait"
    case appStarting = "AppStarting"
    case crosshair = "Crosshair"
    case notAllowed = "No"
    case help = "Help"
    case sizeNS = "SizeNS"
    case sizeWE = "SizeWE"
    case sizeNWSE = "SizeNWSE"
    case sizeNESW = "SizeNESW"
    case sizeAll = "SizeAll"
    case upArrow = "UpArrow"
    case pen = "NWPen"

    public var id: String { rawValue }

    var displayName: String {
        switch self {
        case .arrow: return "正常选择 (Arrow)"
        case .ibeam: return "文本选择 (IBeam)"
        case .hand: return "链接选择 (Hand)"
        case .wait: return "忙碌等待 (Wait / Busy)"
        case .appStarting: return "后台运行 (AppStarting)"
        case .crosshair: return "精确选择 (Crosshair)"
        case .notAllowed: return "不可用 / 禁止 (No)"
        case .help: return "帮助选择 (Help)"
        case .sizeNS: return "垂直调整 (SizeNS)"
        case .sizeWE: return "水平调整 (SizeWE)"
        case .sizeNWSE: return "对角调整 1 (SizeNWSE)"
        case .sizeNESW: return "对角调整 2 (SizeNESW)"
        case .sizeAll: return "移动 / 抓手 (SizeAll)"
        case .upArrow: return "候选 / 别名 (UpArrow)"
        case .pen: return "手写 / 复制 (Pen / Copy)"
        }
    }

    var shortName: String {
        switch self {
        case .arrow: return "正常箭头"
        case .ibeam: return "文本输入"
        case .hand: return "手型链接"
        case .wait: return "忙碌转圈"
        case .appStarting: return "后台加载"
        case .crosshair: return "十字准星"
        case .notAllowed: return "禁止操作"
        case .help: return "帮助问号"
        case .sizeNS: return "上下缩放"
        case .sizeWE: return "左右缩放"
        case .sizeNWSE: return "左上右下缩放"
        case .sizeNESW: return "右上左下缩放"
        case .sizeAll: return "四向移动"
        case .upArrow: return "向上候选"
        case .pen: return "手写/复制"
        }
    }

    var systemIcon: String {
        switch self {
        case .arrow: return "cursorarrow"
        case .ibeam: return "character.cursor.ibeam"
        case .hand: return "hand.point.up.left"
        case .wait: return "rays"
        case .appStarting: return "cursorarrow.motionlines"
        case .crosshair: return "plus.viewfinder"
        case .notAllowed: return "nosign"
        case .help: return "questionmark.circle"
        case .sizeNS: return "arrow.up.and.down"
        case .sizeWE: return "arrow.left.and.right"
        case .sizeNWSE: return "arrow.up.left.and.arrow.down.right"
        case .sizeNESW: return "arrow.up.right.and.arrow.down.left"
        case .sizeAll: return "arrow.up.and.down.and.arrow.left.and.right"
        case .upArrow: return "arrow.up"
        case .pen: return "pencil.tip"
        }
    }

    /// Corresponding macOS CoreGraphics / SkyLight cursor identifiers.
    /// Includes both legacy keys and modern macOS (Sonoma/Sequoia/Tahoe/macOS 27) compatibility keys.
    var macOSIdentifiers: [String] {
        switch self {
        case .arrow:
            return [
                "com.apple.coregraphics.Arrow",
                "com.apple.coregraphics.ArrowS"
            ]
        case .ibeam:
            return [
                "com.apple.coregraphics.IBeam",
                "com.apple.coregraphics.IBeamS",
                "com.apple.coregraphics.IBeamXOR",
                "com.apple.cursor.26"
            ]
        case .hand:
            return [
                "com.apple.cursor.13" // PointingHand
            ]
        case .wait:
            return [
                "com.apple.coregraphics.Wait"
            ]
        case .appStarting:
            return [
                "com.apple.cursor.4" // BusyButClickable
            ]
        case .crosshair:
            return [
                "com.apple.cursor.7",
                "com.apple.cursor.8",
                "com.apple.cursor.20"
            ]
        case .notAllowed:
            return [
                "com.apple.cursor.3" // NotAllowed
            ]
        case .help:
            return [
                "com.apple.cursor.40" // Help
            ]
        case .sizeNS:
            return [
                "com.apple.cursor.21",
                "com.apple.cursor.22",
                "com.apple.cursor.23",
                "com.apple.cursor.31",
                "com.apple.cursor.32",
                "com.apple.cursor.36"
            ]
        case .sizeWE:
            return [
                "com.apple.cursor.17",
                "com.apple.cursor.18",
                "com.apple.cursor.19",
                "com.apple.cursor.27",
                "com.apple.cursor.28",
                "com.apple.cursor.38"
            ]
        case .sizeNWSE:
            return [
                "com.apple.cursor.29",
                "com.apple.cursor.30",
                "com.apple.cursor.33",
                "com.apple.cursor.35"
            ]
        case .sizeNESW:
            return [
                "com.apple.cursor.34",
                "com.apple.cursor.37"
            ]
        case .sizeAll:
            return [
                "com.apple.coregraphics.Move",
                "com.apple.cursor.39",
                "com.apple.cursor.11",
                "com.apple.cursor.12"
            ]
        case .upArrow:
            return [
                "com.apple.coregraphics.Alias",
                "com.apple.cursor.2"
            ]
        case .pen:
            return [
                "com.apple.coregraphics.Copy",
                "com.apple.cursor.1",
                "com.apple.cursor.5"
            ]
        }
    }

    /// Standard positional order in Windows `HKCU,"Control Panel\Cursors",Scheme Source` (INF files)
    /// In Windows INF files, the 15 standard scheme slots are ordered as:
    /// pointer, help, work, busy, cross, text, Hand, unavailiable, Vert, Horz, Dgn1, Dgn2, move, alternate, link
    static let windowsInfSchemeOrder: [CursorRole] = [
        .arrow,       // 0: pointer / Normal
        .help,        // 1: help
        .appStarting, // 2: work / AppStarting
        .wait,        // 3: busy / Wait
        .crosshair,   // 4: cross
        .ibeam,       // 5: text / IBeam
        .pen,         // 6: Hand / NWPen (Handwriting)
        .notAllowed,  // 7: unavailiable / No
        .sizeNS,      // 8: Vert / SizeNS
        .sizeWE,      // 9: Horz / SizeWE
        .sizeNWSE,    // 10: Dgn1 / SizeNWSE
        .sizeNESW,    // 11: Dgn2 / SizeNESW
        .sizeAll,     // 12: move / SizeAll
        .upArrow,     // 13: alternate / UpArrow
        .hand         // 14: link / Hand (Link Select)
    ]

    /// Match a Windows INF variable name or registry key or filename to a CursorRole.
    static func match(identifierOrFilename raw: String) -> CursorRole? {
        let s = raw
            .lowercased()
            .replacingOccurrences(of: ".cur", with: "")
            .replacingOccurrences(of: ".ani", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Exact INF / registry key matches first
        switch s {
        case "pointer", "normal", "arrow", "normalselect", "normal select", "default":
            return .arrow
        case "text", "ibeam", "textselect", "text select", "beam":
            return .ibeam
        case "link", "linkselect", "link select", "pointinghand", "url":
            return .hand
        case "busy", "wait":
            return .wait
        case "work", "working", "appstarting", "background", "workinginbackground":
            return .appStarting
        case "cross", "crosshair", "precision", "precisionselect":
            return .crosshair
        case "no", "unavail", "unavailable", "unavailiable", "notallowed", "forbidden":
            return .notAllowed
        case "help", "helpselect", "question":
            return .help
        case "vert", "vertical", "sizens", "ns", "vresize", "resize_ns":
            return .sizeNS
        case "horz", "horiz", "horizontal", "sizewe", "we", "ew", "hresize", "resize_we":
            return .sizeWE
        case "dgn1", "diagonal1", "sizenwse", "nwse", "dresize1", "resize_nwse":
            return .sizeNWSE
        case "dgn2", "diagonal2", "sizenesw", "nesw", "dresize2", "resize_nesw":
            return .sizeNESW
        case "move", "sizeall", "fleur", "grab":
            return .sizeAll
        case "alternate", "alt", "uparrow", "up", "alias":
            return .upArrow
        case "handwriting", "nwpen", "pen", "pencil", "copy":
            return .pen
        case "hand":
            // Note: in standalone filenames, "hand.cur" almost always means Link Select
            return .hand
        default:
            break
        }

        // 2. Substring / heuristic matching (ordered from specific to general)
        if s.contains("nwse") || s.contains("dgn1") || s.contains("diag1") || s.contains("dresize1") || s.contains("对角线1") || s.contains("对角1") || s.contains("左上") {
            return .sizeNWSE
        }
        if s.contains("nesw") || s.contains("dgn2") || s.contains("diag2") || s.contains("dresize2") || s.contains("对角线2") || s.contains("对角2") || s.contains("右上") {
            return .sizeNESW
        }
        if s.contains("sizens") || s.contains("vert") || s.contains("vresize") || s.contains("northsouth") || s.contains("上下") || s.contains("垂直") {
            return .sizeNS
        }
        if s.contains("sizewe") || s.contains("horz") || s.contains("horiz") || s.contains("hresize") || s.contains("eastwest") || s.contains("leftright") || s.contains("左右") || s.contains("水平") {
            return .sizeWE
        }
        if s.contains("appstart") || s.contains("working") || s.contains("work") || s.contains("后台") {
            return .appStarting
        }
        if s.contains("busy") || s.contains("wait") || s.contains("loading") || s.contains("忙") || s.contains("等待") {
            return .wait
        }
        if s.contains("unavail") || s.contains("notallow") || s.contains("forbid") || s.contains("disabled") || s.contains("不可用") || s.contains("禁止") {
            return .notAllowed
        }
        if s.contains("ibeam") || s.contains("text") || s.contains("beam") || s.contains("文本") || s.contains("输入") {
            return .ibeam
        }
        if s.contains("link") || s.contains("pointing") || s.contains("hand") || s.contains("链接") || s.contains("手型") || s.contains("超链接") {
            if !s.contains("write") && !s.contains("pen") && !s.contains("手写") {
                return .hand
            }
        }
        if s.contains("cross") || s.contains("precis") || s.contains("精确") || s.contains("十字") {
            return .crosshair
        }
        if s.contains("help") || s.contains("question") || s.contains("帮助") || s.contains("问号") {
            return .help
        }
        if s.contains("move") || s.contains("sizeall") || s.contains("移动") {
            return .sizeAll
        }
        if s.contains("up") || s.contains("alt") || s.contains("候选") || s.contains("替代") {
            return .upArrow
        }
        if s.contains("pen") || s.contains("write") || s.contains("手写") || s.contains("笔") {
            return .pen
        }
        if s.contains("arrow") || s.contains("normal") || s.contains("pointer") || s.contains("default") || s.contains("正常") || s.contains("普通") || s.contains("箭头") || s.contains("默认") {
            return .arrow
        }

        return nil
    }

    /// Match a macOS CoreGraphics cursor identifier back to a primary CursorRole
    static func fromMacOSIdentifier(_ id: String) -> CursorRole? {
        for role in CursorRole.allCases {
            if role.macOSIdentifiers.contains(id) {
                return role
            }
        }
        return nil
    }
}

/// Represents a decoded cursor asset (from `.cur`, `.ani`, or `.cape`)
public struct ParsedCursor: Identifiable, Codable {
    public var id: UUID = UUID()
    var sourceFileName: String
    /// Individual animation frames (1 frame for static `.cur`, N frames for `.ani`) encoded as PNG Data
    var framePNGs: [Data]
    /// Original pixel width of a single frame
    var pixelWidth: Int
    /// Original pixel height of a single frame
    var pixelHeight: Int
    /// Hotspot X in original pixel coordinates (`0 ... pixelWidth`)
    var hotspotX: Double
    /// Hotspot Y in original pixel coordinates (`0 ... pixelHeight`)
    var hotspotY: Double
    /// Duration of each frame in seconds (`0` for static cursors)
    var frameDuration: Double

    public var frameCount: Int {
        max(1, framePNGs.count)
    }

    var isAnimated: Bool {
        framePNGs.count > 1 && frameDuration > 0
    }

    /// Decodes `framePNGs` into `CGImage` instances
    func decodeCGImages() -> [CGImage] {
        framePNGs.compactMap { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
    }

    /// Encodes a `CGImage` to PNG `Data`
    static func encodePNG(_ image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(mutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        return mutableData as Data
    }
}

///Logical point size presets for macOS cursors
enum CursorPointSizePreset: Double, CaseIterable, Codable, Identifiable {
    case small20 = 20.0
    case retina24 = 24.0
    case medium28 = 28.0
    case standard32 = 32.0
    case large40 = 40.0
    case extraLarge48 = 48.0

    var id: Double { rawValue }

    var label: String {
        switch self {
        case .small20: return "20 pt (紧凑小号)"
        case .retina24: return "24 pt (Retina 推荐)"
        case .medium28: return "28 pt (macOS 均衡)"
        case .standard32: return "32 pt (Windows 原生)"
        case .large40: return "40 pt (大号指针)"
        case .extraLarge48: return "48 pt (超大清晰)"
        }
    }
}

/// Complete cursor theme containing mapped roles and metadata
public struct CursorTheme: Identifiable, Codable {
    public var id: UUID = UUID()
    public var name: String
    var author: String
    var version: Double = 1.0
    var createdAt: Date = Date()
    /// Logical point height/width target on macOS (e.g. 24pt or 32pt)
    var targetPointSize: Double = CursorPointSizePreset.retina24.rawValue
    /// Mapped cursors keyed by `CursorRole.rawValue`
    var cursors: [String: ParsedCursor] = [:]

    public func cursor(for role: CursorRole) -> ParsedCursor? {
        cursors[role.rawValue]
    }

    mutating func setCursor(_ cursor: ParsedCursor?, for role: CursorRole) {
        if let cursor = cursor {
            cursors[role.rawValue] = cursor
        } else {
            cursors.removeValue(forKey: role.rawValue)
        }
    }

    public var assignedRolesCount: Int {
        cursors.count
    }

    public var animatedRolesCount: Int {
        cursors.values.filter { $0.isAnimated }.count
    }
}
