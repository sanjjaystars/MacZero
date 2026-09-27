import Foundation

public struct DiscoveredExternalGame: Identifiable, Hashable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let mainExecutablePath: String
    public let installDirectory: String
    public let source: GameSource
    public let steamAppId: String?
    public let graphicsApi: GraphicsAPI
    public let architecture: BinaryArchitecture
    public let compatibilityStatus: CompatibilityStatus
    public let compatibilityReason: String?
    public let volumeName: String?
    public let volumeUUID: String?
    public let relativePath: String?
    public let sizeOnDiskBytes: Int64
    public let candidateExecutables: [String]
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        mainExecutablePath: String,
        installDirectory: String,
        source: GameSource,
        steamAppId: String? = nil,
        graphicsApi: GraphicsAPI = .dx12,
        architecture: BinaryArchitecture = .x86_64,
        compatibilityStatus: CompatibilityStatus = .compatible,
        compatibilityReason: String? = nil,
        volumeName: String? = nil,
        volumeUUID: String? = nil,
        relativePath: String? = nil,
        sizeOnDiskBytes: Int64 = 0,
        candidateExecutables: [String] = []
    ) {
        self.id = id
        self.title = title
        self.mainExecutablePath = mainExecutablePath
        self.installDirectory = installDirectory
        self.source = source
        self.steamAppId = steamAppId
        self.graphicsApi = graphicsApi
        self.architecture = architecture
        self.compatibilityStatus = compatibilityStatus
        self.compatibilityReason = compatibilityReason
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.relativePath = relativePath
        self.sizeOnDiskBytes = sizeOnDiskBytes
        self.candidateExecutables = candidateExecutables
    }
}

public enum ScanDepth: String, CaseIterable, Sendable {
    case quick = "Quick Scan"
    case deep = "Deep Scan"
}

public protocol GameFolderScannerProtocol: Sendable {
    func scan(
        url: URL,
        depth: ScanDepth,
        onProgress: (@Sendable (String) -> Void)?
    ) -> [DiscoveredExternalGame]
    
    func detectSteamLibrary(at url: URL) -> [DiscoveredExternalGame]
    func analyzeGameFolder(at folderURL: URL) -> DiscoveredExternalGame?
}

public final class GameFolderScanner: GameFolderScannerProtocol, Sendable {
    public static let shared = GameFolderScanner()
    
    private let binaryInspector: BinaryInspector
    private let manifestParser: SteamManifestParser
    private let loggingService: LoggingService
    
    public init(
        binaryInspector: BinaryInspector = .shared,
        manifestParser: SteamManifestParser = .shared,
        loggingService: LoggingService = .shared
    ) {
        self.binaryInspector = binaryInspector
        self.manifestParser = manifestParser
        self.loggingService = loggingService
    }
    
    public func scan(
        url: URL,
        depth: ScanDepth = .quick,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) -> [DiscoveredExternalGame] {
        loggingService.log("Initiating \(depth.rawValue) on: \(url.path)", level: .info, category: "Scanner")
        onProgress?("Scanning '\(url.lastPathComponent)'...")
        
        var results: [DiscoveredExternalGame] = []
        let fileManager = FileManager.default
        
        // 1. Check if this is directly a Steam library or contains SteamLibrary
        let directSteamGames = detectSteamLibrary(at: url)
        if !directSteamGames.isEmpty {
            loggingService.log("Found \(directSteamGames.count) Steam games directly at: \(url.path)", level: .info, category: "Scanner")
            return directSteamGames
        }
        
        // Check subfolder "SteamLibrary" or "steamapps"
        let potentialSteamDirs = [
            url.appendingPathComponent("SteamLibrary"),
            url.appendingPathComponent("steamapps"),
            url.appendingPathComponent("SteamLibrary/steamapps")
        ]
        for steamDir in potentialSteamDirs {
            if fileManager.fileExists(atPath: steamDir.path) {
                let games = detectSteamLibrary(at: steamDir)
                if !games.isEmpty {
                    results.append(contentsOf: games)
                }
            }
        }
        
        // 2. Scan for Windows game folders (e.g. WindowsGames/, Games/, or direct subdirectories)
        guard let subdirs = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }
        
        for sub in subdirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue else { continue }
            
            // Check if sub is a Steam library
            let steamSub = detectSteamLibrary(at: sub)
            if !steamSub.isEmpty {
                results.append(contentsOf: steamSub)
                continue
            }
            
            // Check if this folder itself is a game installation
            if let game = analyzeGameFolder(at: sub) {
                results.append(game)
            } else if depth == .deep {
                // In deep scan mode, check one more level down (e.g. /Volumes/Games/Action/GameName/)
                if let deepSubdirs = try? fileManager.contentsOfDirectory(at: sub, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for deepSub in deepSubdirs {
                        var deepIsDir: ObjCBool = false
                        if fileManager.fileExists(atPath: deepSub.path, isDirectory: &deepIsDir), deepIsDir.boolValue {
                            if let deepGame = analyzeGameFolder(at: deepSub) {
                                results.append(deepGame)
                            }
                        }
                    }
                }
            }
        }
        
        // Deduplicate by main executable path
        var seenExePaths = Set<String>()
        let uniqueResults = results.filter { game in
            if seenExePaths.contains(game.mainExecutablePath) {
                return false
            }
            seenExePaths.insert(game.mainExecutablePath)
            return true
        }
        
        loggingService.log("Scan finished. Found \(uniqueResults.count) game(s).", level: .info, category: "Scanner")
        return uniqueResults
    }
    
    public func detectSteamLibrary(at url: URL) -> [DiscoveredExternalGame] {
        let fileManager = FileManager.default
        var steamappsURL = url
        
        if url.lastPathComponent == "SteamLibrary" {
            steamappsURL = url.appendingPathComponent("steamapps")
        } else if url.lastPathComponent != "steamapps" {
            let candidate = url.appendingPathComponent("steamapps")
            if fileManager.fileExists(atPath: candidate.path) {
                steamappsURL = candidate
            }
        }
        
        guard fileManager.fileExists(atPath: steamappsURL.path) else {
            return []
        }
        
        guard let files = try? fileManager.contentsOfDirectory(atPath: steamappsURL.path) else {
            return []
        }
        
        let manifestFiles = files.filter { $0.hasPrefix("appmanifest_") && $0.hasSuffix(".acf") }
        var discovered: [DiscoveredExternalGame] = []
        
        let volumeProps = extractVolumeInfo(for: url)
        
        for manifestName in manifestFiles {
            let manifestPath = steamappsURL.appendingPathComponent(manifestName)
            guard let manifest = manifestParser.parse(manifestURL: manifestPath) else { continue }
            
            // Look for game in steamapps/common/<installDir>
            let commonDir = steamappsURL.appendingPathComponent("common").appendingPathComponent(manifest.installDir)
            guard fileManager.fileExists(atPath: commonDir.path) else { continue }
            
            let candidateExes = findExecutables(in: commonDir, maxDepth: 4)
            guard let bestExe = rankBestExecutable(candidates: candidateExes, folderName: manifest.installDir) else {
                continue
            }
            
            let analysis = binaryInspector.inspect(executablePath: bestExe)
            let relPath = bestExe.replacingOccurrences(of: (volumeProps.mountPath ?? ""), with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            
            let game = DiscoveredExternalGame(
                id: "steam-\(manifest.appId)",
                title: manifest.name,
                mainExecutablePath: bestExe,
                installDirectory: commonDir.path,
                source: .steam,
                steamAppId: manifest.appId,
                graphicsApi: analysis.primaryApi,
                architecture: analysis.architecture,
                compatibilityStatus: analysis.recommendedStatus,
                compatibilityReason: analysis.compatibilityReason,
                volumeName: volumeProps.volumeName,
                volumeUUID: volumeProps.volumeUUID,
                relativePath: relPath,
                sizeOnDiskBytes: manifest.sizeOnDisk,
                candidateExecutables: candidateExes
            )
            discovered.append(game)
        }
        
        return discovered
    }
    
    public func analyzeGameFolder(at folderURL: URL) -> DiscoveredExternalGame? {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        
        // Scan for .exe files
        let candidates = findExecutables(in: folderURL, maxDepth: 3)
        guard !candidates.isEmpty else { return nil }
        
        let folderName = folderURL.lastPathComponent
        guard let bestExe = rankBestExecutable(candidates: candidates, folderName: folderName) else {
            return nil
        }
        
        let analysis = binaryInspector.inspect(executablePath: bestExe)
        let volumeProps = extractVolumeInfo(for: folderURL)
        let relPath = bestExe.replacingOccurrences(of: (volumeProps.mountPath ?? ""), with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let cleanedTitle = cleanFolderName(folderName)
        
        return DiscoveredExternalGame(
            title: cleanedTitle,
            mainExecutablePath: bestExe,
            installDirectory: folderURL.path,
            source: .folder,
            steamAppId: nil,
            graphicsApi: analysis.primaryApi,
            architecture: analysis.architecture,
            compatibilityStatus: analysis.recommendedStatus,
            compatibilityReason: analysis.compatibilityReason,
            volumeName: volumeProps.volumeName,
            volumeUUID: volumeProps.volumeUUID,
            relativePath: relPath,
            sizeOnDiskBytes: calculateFolderSize(folderURL),
            candidateExecutables: candidates
        )
    }
    
    private func findExecutables(in directory: URL, maxDepth: Int) -> [String] {
        let fileManager = FileManager.default
        var executables: [String] = []
        
        let resolvedDir = directory.resolvingSymlinksInPath()
        
        guard let enumerator = fileManager.enumerator(
            at: resolvedDir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            if enumerator.level > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            
            if fileURL.pathExtension.lowercased() == "exe" {
                let name = fileURL.lastPathComponent.lowercased()
                if !isIgnoredHelperExecutable(name) {
                    executables.append(fileURL.resolvingSymlinksInPath().path)
                }
            }
        }
        
        return executables
    }

    
    private func isIgnoredHelperExecutable(_ name: String) -> Bool {
        let ignoredPatterns = [
            "unins", "uninstaller", "setup", "installer", "update", "patcher",
            "dxsetup", "vcredist", "vc_redist", "dotnet", "directx",
            "crashpad", "crashreport", "unitycrashhandler", "werfault",
            "easyanticheat", "battleye", "cleanup", "redist", "support"
        ]
        for pattern in ignoredPatterns {
            if name.contains(pattern) {
                return true
            }
        }
        return false
    }
    
    private func rankBestExecutable(candidates: [String], folderName: String) -> String? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        
        let normalizedFolder = folderName.lowercased().replacingOccurrences(of: " ", with: "")
        
        // Score each candidate
        var scored: [(path: String, score: Int)] = []
        
        for path in candidates {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.lowercased()
            let normalizedFile = filename.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
            
            var score = 0
            
            // 1. Name matches or contains folder name
            if normalizedFile == normalizedFolder {
                score += 100
            } else if normalizedFolder.contains(normalizedFile) || normalizedFile.contains(normalizedFolder) {
                score += 50
            }
            
            // 2. Acronym or common game prefix match (e.g. MK12 for Mortal Kombat 1)
            let folderInitials = folderName.components(separatedBy: " ").compactMap { $0.first }.map { String($0).lowercased() }.joined()
            if normalizedFile.hasPrefix(folderInitials) {
                score += 40
            }
            
            // 3. File size check (larger binaries are more likely to be the actual game engine)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                if size > 50 * 1024 * 1024 { // > 50MB
                    score += 30
                } else if size > 10 * 1024 * 1024 { // > 10MB
                    score += 20
                } else if size < 1 * 1024 * 1024 { // < 1MB likely launcher or stub
                    score -= 10
                }
            }
            
            // 4. Check for DirectX / 64-bit PE
            let insp = binaryInspector.inspect(executablePath: path)
            if insp.architecture == .x86_64 {
                score += 15
            }
            if insp.primaryApi == .dx12 || insp.primaryApi == .dx11 {
                score += 25
            }
            
            scored.append((path: path, score: score))
        }
        
        scored.sort { $0.score > $1.score }
        return scored.first?.path
    }
    
    private func extractVolumeInfo(for url: URL) -> (mountPath: String?, volumeName: String?, volumeUUID: String?) {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeUUIDStringKey]
        let values = try? url.resourceValues(forKeys: Set(keys))
        
        let pathComponents = url.pathComponents
        var mountPath: String? = nil
        if pathComponents.count >= 3 && pathComponents[1] == "Volumes" {
            mountPath = "/Volumes/\(pathComponents[2])"
        }
        
        return (
            mountPath: mountPath,
            volumeName: values?.volumeName ?? pathComponents.dropFirst().first,
            volumeUUID: values?.volumeUUIDString
        )
    }
    
    private func calculateFolderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                total += Int64(size)
            }
        }
        return total
    }
    
    private func cleanFolderName(_ name: String) -> String {
        var clean = name.replacingOccurrences(of: "_", with: " ")
        clean = clean.replacingOccurrences(of: "-", with: " ")
        return clean
    }
}
