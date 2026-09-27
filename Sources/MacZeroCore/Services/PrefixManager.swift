import Foundation

public protocol PrefixManagerProtocol: Sendable {
    func getPrefix(forGameId gameId: String) -> GamePrefix?
    func listAllPrefixes() -> [GamePrefix]
    func createPrefix(forGameId gameId: String, name: String, architecture: String) throws -> GamePrefix
    func clonePrefix(sourceGameId: String, targetGameId: String, targetName: String) throws -> GamePrefix
    func backupPrefix(gameId: String, toDestination destinationURL: URL) throws -> URL
    func restorePrefix(fromArchive archiveURL: URL, forGameId gameId: String) throws -> GamePrefix
    func repairPrefix(gameId: String) throws -> GamePrefix
    func resetPrefix(gameId: String) throws -> GamePrefix
    func deletePrefix(gameId: String) throws
    func updateDllOverrides(gameId: String, overrides: [String: String]) throws
}

public extension PrefixManagerProtocol {
    func createPrefix(forGameId gameId: String, name: String, architecture: String = "win64") throws -> GamePrefix {
        return try createPrefix(forGameId: gameId, name: name, architecture: architecture)
    }
}

public final class PrefixManager: PrefixManagerProtocol, Sendable {
    public static let shared = PrefixManager()
    
    private let pathProvider: PathProvider
    
    public init(pathProvider: PathProvider = .shared) {
        self.pathProvider = pathProvider
    }
    
    public func getPrefix(forGameId gameId: String) -> GamePrefix? {
        let prefixURL = pathProvider.prefixPath(forGameId: gameId)
        let metadataURL = prefixURL.appendingPathComponent("maczero_prefix.json")
        
        if let data = try? Data(contentsOf: metadataURL),
           let prefix = try? JSONDecoder().decode(GamePrefix.self, from: data) {
            return prefix
        }
        
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            return GamePrefix(
                id: gameId,
                name: "Prefix \(gameId)",
                path: prefixURL.path,
                wineArchitecture: "win64",
                status: .ready
            )
        }
        return nil
    }
    
    public func listAllPrefixes() -> [GamePrefix] {
        let dir = pathProvider.prefixesDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return items.compactMap { getPrefix(forGameId: $0) }
    }
    
    public func createPrefix(forGameId gameId: String, name: String, architecture: String = "win64") throws -> GamePrefix {
        try pathProvider.ensureDirectoriesExist()
        let prefixURL = pathProvider.prefixPath(forGameId: gameId)
        let fileManager = FileManager.default
        
        if !fileManager.fileExists(atPath: prefixURL.path) {
            try fileManager.createDirectory(at: prefixURL, withIntermediateDirectories: true)
        }
        
        // Setup standard Windows directories inside prefix
        let driveC = prefixURL.appendingPathComponent("drive_c", isDirectory: true)
        let windowsDir = driveC.appendingPathComponent("windows", isDirectory: true)
        let system32 = windowsDir.appendingPathComponent("system32", isDirectory: true)
        let syswow64 = windowsDir.appendingPathComponent("syswow64", isDirectory: true)
        let progFiles = driveC.appendingPathComponent("Program Files", isDirectory: true)
        let usersDir = driveC.appendingPathComponent("users/default", isDirectory: true)
        
        let subDirs = [driveC, windowsDir, system32, syswow64, progFiles, usersDir]
        for sub in subDirs {
            if !fileManager.fileExists(atPath: sub.path) {
                try fileManager.createDirectory(at: sub, withIntermediateDirectories: true)
            }
        }
        
        // Write initial Wine registry templates if not existing
        let systemReg = prefixURL.appendingPathComponent("system.reg")
        if !fileManager.fileExists(atPath: systemReg.path) {
            let regContent = """
            WINE REGISTRY Version 2
            ;; All keys relative to \\\\Machine
            
            [Software\\\\Wine\\\\DllOverrides] 1680000000
            #time=1d9e2b1c7849e00
            "d3d12"="native,builtin"
            "dxgi"="native,builtin"
            "d3d11"="native,builtin"
            """
            try regContent.write(to: systemReg, atomically: true, encoding: .utf8)
        }
        
        let prefix = GamePrefix(
            id: gameId,
            name: name,
            path: prefixURL.path,
            wineArchitecture: architecture,
            status: .ready,
            dllOverrides: [
                "d3d12": "native,builtin",
                "dxgi": "native,builtin",
                "d3d11": "native,builtin"
            ],
            createdAt: Date(),
            lastModified: Date()
        )
        
        try savePrefixMetadata(prefix)
        return prefix
    }
    
    public func clonePrefix(sourceGameId: String, targetGameId: String, targetName: String) throws -> GamePrefix {
        let sourceURL = pathProvider.prefixPath(forGameId: sourceGameId)
        let targetURL = pathProvider.prefixPath(forGameId: targetGameId)
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw NSError(domain: "PrefixManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Source prefix not found: \(sourceGameId)"])
        }
        
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        try fileManager.copyItem(at: sourceURL, to: targetURL)
        
        let existing = getPrefix(forGameId: targetGameId)
        let targetPrefix = GamePrefix(
            id: targetGameId,
            name: targetName,
            path: targetURL.path,
            wineArchitecture: existing?.wineArchitecture ?? "win64",
            status: existing?.status ?? .ready,
            dllOverrides: existing?.dllOverrides ?? [:],
            registryEntries: existing?.registryEntries ?? [:],
            installedDependencies: existing?.installedDependencies ?? [],
            createdAt: Date(),
            lastModified: Date()
        )
        try savePrefixMetadata(targetPrefix)
        return targetPrefix
    }
    
    public func backupPrefix(gameId: String, toDestination destinationURL: URL) throws -> URL {
        let prefixURL = pathProvider.prefixPath(forGameId: gameId)
        guard FileManager.default.fileExists(atPath: prefixURL.path) else {
            throw NSError(domain: "PrefixManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Prefix not found for game: \(gameId)"])
        }
        
        let archiveURL = destinationURL.appendingPathComponent("\(gameId)-backup-\(Int(Date().timeIntervalSince1970)).tar")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-cf", archiveURL.path, "-C", pathProvider.prefixesDirectory.path, gameId]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PrefixManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Tar backup failed with status \(process.terminationStatus)"])
        }
        
        return archiveURL
    }
    
    public func restorePrefix(fromArchive archiveURL: URL, forGameId gameId: String) throws -> GamePrefix {
        let targetURL = pathProvider.prefixPath(forGameId: gameId)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: targetURL.path) {
            try fileManager.removeItem(at: targetURL)
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archiveURL.path, "-C", pathProvider.prefixesDirectory.path]
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PrefixManager", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Tar restore failed."])
        }
        
        return try createPrefix(forGameId: gameId, name: "Restored Prefix (\(gameId))")
    }
    
    public func repairPrefix(gameId: String) throws -> GamePrefix {
        let prefixURL = pathProvider.prefixPath(forGameId: gameId)
        let fileManager = FileManager.default
        
        // Remove stale lock files or corrupted socket pipes
        let lockFiles = [".update-timestamp", ".wine-server-lock", "wineserver.pid"]
        for lock in lockFiles {
            let lockPath = prefixURL.appendingPathComponent(lock)
            if fileManager.fileExists(atPath: lockPath.path) {
                try? fileManager.removeItem(at: lockPath)
            }
        }
        
        // Ensure standard structure is sound
        return try createPrefix(forGameId: gameId, name: "Repaired \(gameId)")
    }
    
    public func resetPrefix(gameId: String) throws -> GamePrefix {
        try deletePrefix(gameId: gameId)
        return try createPrefix(forGameId: gameId, name: "Reset \(gameId)")
    }
    
    public func deletePrefix(gameId: String) throws {
        let prefixURL = pathProvider.prefixPath(forGameId: gameId)
        if FileManager.default.fileExists(atPath: prefixURL.path) {
            try FileManager.default.removeItem(at: prefixURL)
        }
    }
    
    public func updateDllOverrides(gameId: String, overrides: [String: String]) throws {
        guard var prefix = getPrefix(forGameId: gameId) else { return }
        prefix.dllOverrides = overrides
        prefix.lastModified = Date()
        try savePrefixMetadata(prefix)
    }
    
    private func savePrefixMetadata(_ prefix: GamePrefix) throws {
        let prefixURL = URL(fileURLWithPath: prefix.path)
        let metadataURL = prefixURL.appendingPathComponent("maczero_prefix.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(prefix)
        try data.write(to: metadataURL)
    }
}
