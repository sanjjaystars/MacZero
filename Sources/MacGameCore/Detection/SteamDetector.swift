import Foundation

public struct DiscoveredSteamGame: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let appId: String
    public let name: String
    public let installDir: String
    public let fullInstallPath: String
    public let executablePath: String?
    public let isWindowsVersion: Bool
    public let isNativeMacVersion: Bool
    public let hasBothVersions: Bool
    public let sizeOnDiskBytes: Int64
    
    public init(
        appId: String,
        name: String,
        installDir: String,
        fullInstallPath: String,
        executablePath: String?,
        isWindowsVersion: Bool,
        isNativeMacVersion: Bool,
        hasBothVersions: Bool,
        sizeOnDiskBytes: Int64
    ) {
        self.id = "steam-\(appId)"
        self.appId = appId
        self.name = name
        self.installDir = installDir
        self.fullInstallPath = fullInstallPath
        self.executablePath = executablePath
        self.isWindowsVersion = isWindowsVersion
        self.isNativeMacVersion = isNativeMacVersion
        self.hasBothVersions = hasBothVersions
        self.sizeOnDiskBytes = sizeOnDiskBytes
    }
}

public final class SteamDetector: Sendable {
    public static let shared = SteamDetector()
    
    public init() {}
    
    public func detectSteamInstallation() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let steamPath = home.appendingPathComponent("Library/Application Support/Steam")
        if FileManager.default.fileExists(atPath: steamPath.path) {
            return steamPath
        }
        return nil
    }
    
    public func scanSteamLibraries() -> [DiscoveredSteamGame] {
        guard let steamRoot = detectSteamInstallation() else { return [] }
        let libraryVdf = steamRoot.appendingPathComponent("steamapps/libraryfolders.vdf")
        
        var libraryPaths = [steamRoot.appendingPathComponent("steamapps")]
        
        if let vdfContent = try? String(contentsOf: libraryVdf, encoding: .utf8) {
            let parsedPaths = extractLibraryPaths(fromVdf: vdfContent)
            for p in parsedPaths {
                let steamappsURL = URL(fileURLWithPath: p).appendingPathComponent("steamapps")
                if FileManager.default.fileExists(atPath: steamappsURL.path) && !libraryPaths.contains(steamappsURL) {
                    libraryPaths.append(steamappsURL)
                }
            }
        }
        
        var results: [DiscoveredSteamGame] = []
        let fileManager = FileManager.default
        
        for libPath in libraryPaths {
            guard let contents = try? fileManager.contentsOfDirectory(atPath: libPath.path) else { continue }
            let manifestFiles = contents.filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }
            
            for manifestName in manifestFiles {
                let manifestURL = libPath.appendingPathComponent(manifestName)
                if let manifestContent = try? String(contentsOf: manifestURL, encoding: .utf8),
                   let game = parseManifest(content: manifestContent, steamappsPath: libPath) {
                    results.append(game)
                }
            }
        }
        
        return results
    }
    
    private func extractLibraryPaths(fromVdf vdf: String) -> [String] {
        var paths: [String] = []
        let lines = vdf.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("\"path\"") {
                // e.g. "path"		"/Users/user/Library/Application Support/Steam"
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
    
    private func parseManifest(content: String, steamappsPath: URL) -> DiscoveredSteamGame? {
        var appId: String?
        var name: String?
        var installDir: String?
        var sizeOnDisk: Int64 = 0
        
        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmed.components(separatedBy: "\"")
            guard parts.count >= 4 else { continue }
            let key = parts[1].lowercased()
            let value = parts[3]
            
            if key == "appid" {
                appId = value
            } else if key == "name" {
                name = value
            } else if key == "installdir" {
                installDir = value
            } else if key == "sizeondisk" {
                sizeOnDisk = Int64(value) ?? 0
            }
        }
        
        guard let validAppId = appId, let validName = name, let validDir = installDir else {
            return nil
        }
        
        let fullPath = steamappsPath.appendingPathComponent("common").appendingPathComponent(validDir)
        var isWindows = false
        var isMac = false
        var detectedExe: String?
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: fullPath.path) {
            if let enumerator = fileManager.enumerator(at: fullPath, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let fileURL as URL in enumerator {
                    let pathExt = fileURL.pathExtension.lowercased()
                    if pathExt == "exe" {
                        isWindows = true
                        if detectedExe == nil || fileURL.lastPathComponent.lowercased().contains(validDir.lowercased()) {
                            detectedExe = fileURL.path
                        }
                    } else if pathExt == "app" {
                        isMac = true
                    }
                }
            }
        }
        
        // If no .app was found, and it has an .exe, it's a Windows version installed through Steam
        let hasBoth = isWindows && isMac
        
        return DiscoveredSteamGame(
            appId: validAppId,
            name: validName,
            installDir: validDir,
            fullInstallPath: fullPath.path,
            executablePath: detectedExe,
            isWindowsVersion: isWindows,
            isNativeMacVersion: isMac,
            hasBothVersions: hasBoth,
            sizeOnDiskBytes: sizeOnDisk
        )
    }
}
