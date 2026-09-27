import Foundation

public enum GameDriveResolutionError: LocalizedError, Sendable {
    case driveDisconnected(driveName: String)
    case gameFolderMoved(expectedPath: String)
    case executableNotFound(path: String)
    case securityAccessDenied(path: String)
    case readOnlyFilesystem(driveName: String)
    
    public var errorDescription: String? {
        switch self {
        case .driveDisconnected(let name):
            return "Game drive '\(name)' is disconnected. Please connect the external drive to launch this game."
        case .gameFolderMoved(let path):
            return "Game directory was moved or renamed: \(path)"
        case .executableNotFound(let path):
            return "Game Windows executable (.exe) was not found at: \(path)"
        case .securityAccessDenied(let path):
            return "MacZero does not currently have permission to access external folder: \(path)"
        case .readOnlyFilesystem(let name):
            return "External drive '\(name)' is mounted read-only on macOS. MacZero can run the game, but game save data must reside in an internal prefix."
        }
    }
}

public struct ResolvedGameLaunchPath: Sendable {
    public let executableURL: URL
    public let workingDirectoryURL: URL
    public let volumeName: String
    public let isExternal: Bool
    public let isReadOnlyDrive: Bool
    public let securityScopedURL: URL?
    
    public init(
        executableURL: URL,
        workingDirectoryURL: URL,
        volumeName: String,
        isExternal: Bool,
        isReadOnlyDrive: Bool,
        securityScopedURL: URL?
    ) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
        self.volumeName = volumeName
        self.isExternal = isExternal
        self.isReadOnlyDrive = isReadOnlyDrive
        self.securityScopedURL = securityScopedURL
    }
}

public protocol ExternalGamePathResolverProtocol: Sendable {
    func resolveGamePath(game: Game) throws -> ResolvedGameLaunchPath
    func verifyGameAvailability(game: Game) -> (isAvailable: Bool, statusMessage: String)
}

public final class ExternalGamePathResolver: ExternalGamePathResolverProtocol, Sendable {
    public static let shared = ExternalGamePathResolver()
    
    private let driveManager: ExternalDriveManagerProtocol
    private let bookmarkManager: SecurityScopedBookmarkManagerProtocol
    private let loggingService: LoggingService
    
    public init(
        driveManager: ExternalDriveManagerProtocol = ExternalDriveManager.shared,
        bookmarkManager: SecurityScopedBookmarkManagerProtocol = SecurityScopedBookmarkManager.shared,
        loggingService: LoggingService = .shared
    ) {
        self.driveManager = driveManager
        self.bookmarkManager = bookmarkManager
        self.loggingService = loggingService
    }
    
    public func resolveGamePath(game: Game) throws -> ResolvedGameLaunchPath {
        let fileManager = FileManager.default
        
        // 1. If not external, verify local path directly
        if !game.isExternal {
            guard fileManager.fileExists(atPath: game.executablePath) else {
                throw GameDriveResolutionError.executableNotFound(path: game.executablePath)
            }
            let exeURL = URL(fileURLWithPath: game.executablePath)
            let workDirURL = URL(fileURLWithPath: game.workingDirectory ?? exeURL.deletingLastPathComponent().path)
            return ResolvedGameLaunchPath(
                executableURL: exeURL,
                workingDirectoryURL: workDirURL,
                volumeName: "Mac Internal SSD",
                isExternal: false,
                isReadOnlyDrive: false,
                securityScopedURL: nil
            )
        }
        
        // 2. External Game Resolution
        var resolvedBaseURL: URL? = nil
        var isReadOnly = false
        var driveName = game.volumeName ?? "External Game Drive"
        
        // Strategy A: Try resolving security-scoped bookmark if present
        if let bookmarkData = game.securityBookmarkData {
            if let (bookmarkURL, _) = try? bookmarkManager.resolveBookmark(data: bookmarkData) {
                _ = bookmarkManager.startAccessing(url: bookmarkURL)
                resolvedBaseURL = bookmarkURL
                loggingService.log("Resolved security bookmark for '\(game.title)' to: \(bookmarkURL.path)", level: .debug, category: "PathResolver")
            }
        }
        
        // Strategy B: Match connected external drive by volume UUID or Volume Name
        if let driveUUID = game.volumeUUID, let drive = driveManager.getDrive(byId: driveUUID) {
            driveName = drive.name
            isReadOnly = drive.isReadOnly
            if !drive.isConnected {
                throw GameDriveResolutionError.driveDisconnected(driveName: drive.name)
            }
            if resolvedBaseURL == nil {
                resolvedBaseURL = URL(fileURLWithPath: drive.mountPath)
            }
        } else if let drive = driveManager.getDrive(forPath: game.executablePath) {
            driveName = drive.name
            isReadOnly = drive.isReadOnly
            if !drive.isConnected {
                throw GameDriveResolutionError.driveDisconnected(driveName: drive.name)
            }
        }
        
        // Strategy C: Determine actual executable path
        var finalExePath = game.executablePath
        
        // If relative path is available and base URL resolved, reconstruct path
        if let relPath = game.relativePath, let base = resolvedBaseURL {
            let candidate = base.appendingPathComponent(relPath).path
            if fileManager.fileExists(atPath: candidate) {
                finalExePath = candidate
            }
        }
        
        // If original path doesn't exist, try searching under resolved base volume
        if !fileManager.fileExists(atPath: finalExePath) {
            if let base = resolvedBaseURL {
                let candidateURL = base.appendingPathComponent(URL(fileURLWithPath: game.executablePath).lastPathComponent)
                if fileManager.fileExists(atPath: candidateURL.path) {
                    finalExePath = candidateURL.path
                }
            }
        }
        
        // Check if executable exists at final calculated path
        guard fileManager.fileExists(atPath: finalExePath) else {
            // Check if entire drive is missing
            if let volName = game.volumeName, !fileManager.fileExists(atPath: "/Volumes/\(volName)") {
                throw GameDriveResolutionError.driveDisconnected(driveName: volName)
            }
            throw GameDriveResolutionError.executableNotFound(path: finalExePath)
        }
        
        let exeURL = URL(fileURLWithPath: finalExePath)
        let workDirURL = URL(fileURLWithPath: game.workingDirectory ?? exeURL.deletingLastPathComponent().path)
        
        return ResolvedGameLaunchPath(
            executableURL: exeURL,
            workingDirectoryURL: workDirURL,
            volumeName: driveName,
            isExternal: true,
            isReadOnlyDrive: isReadOnly,
            securityScopedURL: resolvedBaseURL
        )
    }
    
    public func verifyGameAvailability(game: Game) -> (isAvailable: Bool, statusMessage: String) {
        do {
            let _ = try resolveGamePath(game: game)
            return (true, "Ready to Play")
        } catch let err as GameDriveResolutionError {
            return (false, err.localizedDescription)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
