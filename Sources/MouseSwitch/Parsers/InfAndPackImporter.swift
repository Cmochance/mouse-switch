import Foundation

enum ThemeImportError: LocalizedError {
    case noCursorFilesFound
    case invalidCapeFile(String)

    var errorDescription: String? {
        switch self {
        case .noCursorFilesFound:
            return "在所选路径中未找到任何可用的 .cur、.ani 或 .cape 光标文件"
        case .invalidCapeFile(let msg):
            return "无效的 .cape 文件: \(msg)"
        }
    }
}

/// Imports Windows cursor packs (folder, `install.inf`, individual `.cur`/`.ani`) or macOS `.cape` files into a `CursorTheme`.
public enum InfAndPackImporter {

    /// Import from any file or directory URL
    public static func importFrom(url: URL) throws -> CursorTheme {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        if isDir.boolValue {
            return try importDirectory(url)
        }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "inf":
            return try importDirectory(url.deletingLastPathComponent(), preferredInfURL: url)
        case "cape":
            return try CapeCoder.importCape(from: url)
        case "cur", "ani", "ico":
            let parsed = try WinCursorParser.parse(fileURL: url)
            let baseName = url.deletingPathExtension().lastPathComponent
            let role = CursorRole.match(identifierOrFilename: baseName) ?? .arrow
            var theme = CursorTheme(
                name: baseName,
                author: "Windows Import"
            )
            theme.setCursor(parsed, for: role)
            return theme
        default:
            throw ThemeImportError.noCursorFilesFound
        }
    }

    /// Import an entire directory containing `.cur` / `.ani` files and optional `.inf` installer script
    public static func importDirectory(_ dirURL: URL, preferredInfURL: URL? = nil) throws -> CursorTheme {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        // Find all cursor files in the directory (case-insensitive map by filename)
        var cursorFilesByLowerName: [String: URL] = [:]
        var allCursorURLs: [URL] = []
        var infURLs: [URL] = []

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            if ext == "cur" || ext == "ani" || ext == "ico" {
                cursorFilesByLowerName[fileURL.lastPathComponent.lowercased()] = fileURL
                allCursorURLs.append(fileURL)
            } else if ext == "inf" {
                infURLs.append(fileURL)
            } else if ext == "cape", allCursorURLs.isEmpty {
                return try CapeCoder.importCape(from: fileURL)
            }
        }

        guard !allCursorURLs.isEmpty else {
            throw ThemeImportError.noCursorFilesFound
        }

        var themeName = dirURL.lastPathComponent
        var mappedFileURLs: [CursorRole: URL] = [:]

        // 1. Parse .inf file if present
        let targetInf = preferredInfURL ?? infURLs.first
        if let infURL = targetInf, let infText = readTextWithAutoEncoding(from: infURL) {
            let infResult = parseInfContent(infText, availableFiles: cursorFilesByLowerName)
            if let schemeName = infResult.schemeName, !schemeName.isEmpty {
                themeName = schemeName
            }
            for (role, fileURL) in infResult.roleMap {
                mappedFileURLs[role] = fileURL
            }
        }

        // 2. Heuristic filename matching for any unmapped cursor files in the folder
        var usedURLs = Set(mappedFileURLs.values.map { $0.standardizedFileURL })
        for fileURL in allCursorURLs {
            let stdURL = fileURL.standardizedFileURL
            guard !usedURLs.contains(stdURL) else { continue }
            let stem = fileURL.deletingPathExtension().lastPathComponent
            if let role = CursorRole.match(identifierOrFilename: stem), mappedFileURLs[role] == nil {
                mappedFileURLs[role] = fileURL
                usedURLs.insert(stdURL)
            }
        }

        // 3. If still nothing matched (e.g. single file with arbitrary name), assign first to .arrow
        if mappedFileURLs.isEmpty, let firstURL = allCursorURLs.first {
            mappedFileURLs[.arrow] = firstURL
        }

        // 4. Parse all mapped cursor files
        var theme = CursorTheme(
            name: themeName,
            author: "Windows Cursor Pack"
        )

        for (role, fileURL) in mappedFileURLs {
            let parsed = try WinCursorParser.parse(fileURL: fileURL)
            theme.setCursor(parsed, for: role)
        }

        guard theme.assignedRolesCount > 0 else {
            throw ThemeImportError.noCursorFilesFound
        }

        return theme
    }

    // MARK: - .INF Parser

    private struct InfParseResult {
        var schemeName: String?
        var roleMap: [CursorRole: URL] = [:]
    }

    private static func parseInfContent(
        _ content: String,
        availableFiles: [String: URL]
    ) -> InfParseResult {
        var result = InfParseResult()
        var stringsDict: [String: String] = [:]
        var currentSection = ""

        let lines = content.components(separatedBy: .newlines)

        // First pass: collect [Strings]
        for rawLine in lines {
            let line = stripInfComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                currentSection = String(line.dropFirst().dropLast()).lowercased()
                continue
            }

            if currentSection == "strings", let eqIndex = line.firstIndex(of: "=") {
                let key = line[..<eqIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rawVal = line[line.index(after: eqIndex)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                stringsDict[key] = rawVal

                if key == "scheme_name" || key == "schemename" || key == "cur_name" {
                    result.schemeName = rawVal
                }
            }
        }

        // Helper to resolve %VAR% and locate filename in `availableFiles`
        func resolveFileURL(_ rawExpr: String) -> URL? {
            var resolved = rawExpr.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            for (k, v) in stringsDict {
                resolved = resolved.replacingOccurrences(
                    of: "%\(k)%",
                    with: v,
                    options: [.caseInsensitive]
                )
            }
            // Extract basename after any backslash or slash
            let parts = resolved.components(separatedBy: CharacterSet(charactersIn: "\\/"))
            guard let fileName = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !fileName.isEmpty else {
                return nil
            }
            return availableFiles[fileName]
        }

        // Second pass: inspect HKCU,"Control Panel\Cursors" lines
        for rawLine in lines {
            let line = stripInfComment(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.lowercased().contains("control panel\\cursors") else { continue }

            // Example 1 (Named registry key):
            // HKCU,"Control Panel\Cursors",Arrow,0x00020000,"%10%\%CUR_DIR%\%pointer%"
            // Example 2 (Scheme positional list):
            // HKCU,"Control Panel\Cursors\Schemes","%SCHEME_NAME%",0x00020000,"%10%\%CUR_DIR%\%pointer%,%10%\%CUR_DIR%\%help%,..."
            let fields = splitCSVRespectingQuotes(line)
            if line.lowercased().contains("control panel\\cursors\\schemes"), fields.count >= 5 {
                let schemeListRaw = fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let items = schemeListRaw.components(separatedBy: ",")
                for (idx, item) in items.enumerated() where idx < CursorRole.windowsInfSchemeOrder.count {
                    let role = CursorRole.windowsInfSchemeOrder[idx]
                    if let url = resolveFileURL(item) {
                        result.roleMap[role] = url
                    }
                }
            } else if fields.count >= 5 {
                let regKeyName = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
                let valueExpr = fields[4]
                if let role = CursorRole.match(identifierOrFilename: regKeyName),
                   let url = resolveFileURL(valueExpr) {
                    result.roleMap[role] = url
                }
            }
        }

        // Third pass: match directly from [Strings] keys (e.g. pointer = "Normal.cur")
        for (key, val) in stringsDict {
            if let role = CursorRole.match(identifierOrFilename: key),
               result.roleMap[role] == nil,
               let url = resolveFileURL(val) {
                result.roleMap[role] = url
            }
        }

        return result
    }

    private static func stripInfComment(_ line: String) -> String {
        var inQuotes = false
        for (i, ch) in line.enumerated() {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == ";" && !inQuotes {
                let idx = line.index(line.startIndex, offsetBy: i)
                return String(line[..<idx])
            }
        }
        return line
    }

    private static func splitCSVRespectingQuotes(_ line: String) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                current.append(ch)
            } else if ch == "," && !inQuotes {
                results.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        results.append(current.trimmingCharacters(in: .whitespaces))
        return results
    }

    /// Reads text file trying UTF-8, UTF-16, GB18030 (Chinese Windows default), and Windows-1252
    private static func readTextWithAutoEncoding(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))),
            .windowsCP1252,
            .isoLatin1
        ]
        for enc in encodings {
            if let str = String(data: data, encoding: enc) {
                return str
            }
        }
        return nil
    }
}
