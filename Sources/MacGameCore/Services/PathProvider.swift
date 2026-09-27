import Foundation

public final class PathProvider: Sendable {
    public static let shared = PathProvider()
    
    public let rootDirectory: URL
    public let runtimesDirectory: URL
    public let gamesDirectory: URL
    public let prefixesDirectory: URL
    public let cacheDirectory: URL
    public let downloadsDirectory: URL
    public let logsDirectory: URL
    public let configDirectory: URL
    public let profilesDirectory: URL
    
    public init(customRoot: URL? = nil) {
        if let custom = customRoot {
            self.rootDirectory = custom
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.rootDirectory = appSupport.appendingPathComponent("MacGame", isDirectory: true)
        }
        
        self.runtimesDirectory = rootDirectory.appendingPathComponent("runtimes", isDirectory: true)
        self.gamesDirectory = rootDirectory.appendingPathComponent("games", isDirectory: true)
        self.prefixesDirectory = rootDirectory.appendingPathComponent("prefixes", isDirectory: true)
        self.cacheDirectory = rootDirectory.appendingPathComponent("cache", isDirectory: true)
        self.downloadsDirectory = rootDirectory.appendingPathComponent("downloads", isDirectory: true)
        self.logsDirectory = rootDirectory.appendingPathComponent("logs", isDirectory: true)
        self.configDirectory = rootDirectory.appendingPathComponent("config", isDirectory: true)
        self.profilesDirectory = rootDirectory.appendingPathComponent("profiles", isDirectory: true)
    }
    
    public func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        let dirs = [
            rootDirectory,
            runtimesDirectory,
            gamesDirectory,
            prefixesDirectory,
            cacheDirectory,
            downloadsDirectory,
            logsDirectory,
            configDirectory,
            profilesDirectory
        ]
        
        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
            }
        }
    }
    
    public func prefixPath(forGameId gameId: String) -> URL {
        return prefixesDirectory.appendingPathComponent(gameId, isDirectory: true)
    }
    
    public func logPath(forGameId gameId: String) -> URL {
        return logsDirectory.appendingPathComponent("\(gameId).log")
    }
}
