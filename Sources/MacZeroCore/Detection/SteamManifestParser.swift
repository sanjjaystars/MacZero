import Foundation

public struct ParsedSteamManifest: Equatable, Sendable {
    public let appId: String
    public let name: String
    public let installDir: String
    public let sizeOnDisk: Int64
    public let buildId: String?
    
    public init(appId: String, name: String, installDir: String, sizeOnDisk: Int64, buildId: String? = nil) {
        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.sizeOnDisk = sizeOnDisk
        self.buildId = buildId
    }
}

public final class SteamManifestParser: Sendable {
    public static let shared = SteamManifestParser()
    
    public init() {}
    
    public func parse(manifestURL: URL) -> ParsedSteamManifest? {
        guard let content = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return nil
        }
        return parse(content: content)
    }
    
    public func parse(content: String) -> ParsedSteamManifest? {
        var appId: String?
        var name: String?
        var installDir: String?
        var sizeOnDisk: Int64 = 0
        var buildId: String?
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: "\"")
            guard parts.count >= 4 else { continue }
            let key = parts[1].lowercased()
            let value = parts[3]
            
            switch key {
            case "appid":
                appId = value
            case "name":
                name = value
            case "installdir":
                installDir = value
            case "sizeondisk":
                sizeOnDisk = Int64(value) ?? 0
            case "buildid":
                buildId = value
            default:
                break
            }
        }
        
        guard let validAppId = appId, let validName = name, let validDir = installDir else {
            return nil
        }
        
        return ParsedSteamManifest(
            appId: validAppId,
            name: validName,
            installDir: validDir,
            sizeOnDisk: sizeOnDisk,
            buildId: buildId
        )
    }
    
    public func parseLibraryFolders(vdfURL: URL) -> [String] {
        guard let content = try? String(contentsOf: vdfURL, encoding: .utf8) else {
            return []
        }
        return parseLibraryFolders(content: content)
    }
    
    public func parseLibraryFolders(content: String) -> [String] {
        var paths: [String] = []
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("\"path\"") {
                let parts = trimmed.components(separatedBy: "\"")
                if parts.count >= 4 {
                    let path = parts[3]
                    if !paths.contains(path) {
                        paths.append(path)
                    }
                }
            }
        }
        return paths
    }
}
