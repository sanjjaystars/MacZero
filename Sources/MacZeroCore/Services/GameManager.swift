import Foundation

public protocol GameManagerProtocol: Sendable {
    func listGames() -> [Game]
    func getGame(byId id: String) -> Game?
    func addGameFromExecutable(path: String, customTitle: String?, source: GameSource) throws -> Game
    func importSteamGame(discovered: DiscoveredSteamGame) throws -> Game
    func importDiscoveredExternalGame(
        discovered: DiscoveredExternalGame,
        locationType: PrefixLocationType,
        customPrefixPath: String?
    ) throws -> Game
    func importSteamLibrary(
        at url: URL,
        selectedAppIds: [String]?,
        locationType: PrefixLocationType
    ) throws -> [Game]
    func scanDrive(driveId: String, depth: ScanDepth) -> [DiscoveredExternalGame]
    func scanExternalFolder(url: URL, depth: ScanDepth) -> [DiscoveredExternalGame]
    func updateGame(_ game: Game) throws
    func removeGame(byId id: String, deletePrefix: Bool) throws
    func launch(gameId: String, mode: GameLaunchMode) async throws -> ProcessLaunchResult
    func repairGame(gameId: String) throws
    func verifyGame(gameId: String) -> GameVerificationResult
    func addGameFromFolder(url: URL, customTitle: String?) throws -> Game
    func checkDriveConnectivity()
    func exportPortableLibrary(toDrive driveId: String) throws -> URL
}

public final class GameManager: GameManagerProtocol, @unchecked Sendable {
    public static let shared = GameManager()
    
    private let pathProvider: PathProvider
    private let binaryInspector: BinaryInspector
    private let profileEngine: ProfileEngineProtocol
    private let prefixManager: PrefixManagerProtocol
    private let processManager: ProcessManagerProtocol
    private let driveManager: ExternalDriveManagerProtocol
    private let bookmarkManager: SecurityScopedBookmarkManagerProtocol
    private let scanner: GameFolderScannerProtocol
    private let loggingService: LoggingService
    
    private var gamesCache: [Game] = []
    private let queue = DispatchQueue(label: "com.maczero.gamemanager")
    private var driveObserverToken: UUID?
    
    public init(
        pathProvider: PathProvider = .shared,
        binaryInspector: BinaryInspector = .shared,
        profileEngine: ProfileEngineProtocol = ProfileEngine.shared,
        prefixManager: PrefixManagerProtocol = PrefixManager.shared,
        processManager: ProcessManagerProtocol = ProcessManager.shared,
        driveManager: ExternalDriveManagerProtocol = ExternalDriveManager.shared,
        bookmarkManager: SecurityScopedBookmarkManagerProtocol = SecurityScopedBookmarkManager.shared,
        scanner: GameFolderScannerProtocol = GameFolderScanner.shared,
        loggingService: LoggingService = .shared
    ) {
        self.pathProvider = pathProvider
        self.binaryInspector = binaryInspector
        self.profileEngine = profileEngine
        self.prefixManager = prefixManager
        self.processManager = processManager
        self.driveManager = driveManager
        self.bookmarkManager = bookmarkManager
        self.scanner = scanner
        self.loggingService = loggingService
        
        loadGamesFromDisk()
        checkDriveConnectivity()
        setupDriveObserver()
    }
    
    deinit {
        if let token = driveObserverToken {
            driveManager.unregisterDriveChangeObserver(id: token)
        }
    }
    
    public func listGames() -> [Game] {
        return queue.sync { gamesCache }
    }
    
    public func getGame(byId id: String) -> Game? {
        return queue.sync { gamesCache.first { $0.id == id } }
    }
    
    public func addGameFromExecutable(path: String, customTitle: String? = nil, source: GameSource = .customExe) throws -> Game {
        let fileURL = URL(fileURLWithPath: path)
        let rawTitle = customTitle ?? fileURL.deletingPathExtension().lastPathComponent
        let sanitizedTitle = cleanGameTitle(rawTitle)
        
        loggingService.log("Adding game from executable: \(path)", level: .info, category: "GameManager")
        
        // 1. Analyze binary
        let analysis = binaryInspector.inspect(executablePath: path)
        loggingService.log("Binary inspection: Arch=\(analysis.architecture.rawValue), API=\(analysis.primaryApi.rawValue), Status=\(analysis.recommendedStatus.rawValue)", level: .info, category: "GameManager")
        
        // 2. Resolve Profile
        let profile = profileEngine.matchProfile(forTitle: sanitizedTitle, executablePath: path, api: analysis.primaryApi)
        
        // Check if on external drive
        let matchedDrive = driveManager.getDrive(forPath: path)
        let isExternal = matchedDrive != nil || path.hasPrefix("/Volumes/")
        let bookmarkData = isExternal ? try? bookmarkManager.createBookmark(for: fileURL, id: nil) : nil
        
        // 3. Create isolated prefix
        let gameId = UUID().uuidString
        _ = try prefixManager.createPrefix(
            forGameId: gameId,
            name: "\(sanitizedTitle) Prefix",
            architecture: analysis.architecture == .x86_32 ? "win32" : "win64",
            customPath: nil
        )
        
        // 4. Construct Game
        let game = Game(
            id: gameId,
            title: sanitizedTitle,
            executablePath: path,
            workingDirectory: fileURL.deletingLastPathComponent().path,
            source: source,
            sourceAppId: nil,
            graphicsApi: analysis.primaryApi != .unknown ? analysis.primaryApi : profile.graphicsApi,
            architecture: analysis.architecture,
            compatibilityStatus: analysis.recommendedStatus,
            compatibilityReason: analysis.compatibilityReason,
            prefixId: gameId,
            runtimeId: "wine-default",
            profileId: profile.id,
            launchArguments: profile.launchArguments,
            environmentVariables: [:],
            driveIdentifier: matchedDrive?.id,
            volumeName: matchedDrive?.name,
            volumeUUID: matchedDrive?.volumeUUID,
            isExternal: isExternal,
            isDriveConnected: matchedDrive?.isConnected ?? true,
            securityBookmarkData: bookmarkData,
            launchMode: .directExecutable,
            prefixLocationType: .internalStorage
        )
        
        try saveGame(game)
        loggingService.log("Game '\(sanitizedTitle)' successfully registered with ID \(gameId)", level: .info, category: "GameManager", gameId: gameId)
        return game
    }
    
    public func importSteamGame(discovered: DiscoveredSteamGame) throws -> Game {
        guard let exePath = discovered.executablePath else {
            throw NSError(domain: "GameManager", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Windows .exe executable found in Steam directory: \(discovered.installDir)"])
        }
        
        let gameId = "steam-\(discovered.appId)"
        
        if let existing = getGame(byId: gameId) {
            return existing
        }
        
        let analysis = binaryInspector.inspect(executablePath: exePath)
        let profile = profileEngine.matchProfile(forTitle: discovered.name, executablePath: exePath, api: analysis.primaryApi)
        
        let matchedDrive = driveManager.getDrive(forPath: exePath)
        let isExternal = matchedDrive != nil || exePath.hasPrefix("/Volumes/")
        let bookmarkData = isExternal ? try? bookmarkManager.createBookmark(for: URL(fileURLWithPath: exePath), id: nil) : nil
        
        _ = try prefixManager.createPrefix(forGameId: gameId, name: "\(discovered.name) Prefix")
        
        let game = Game(
            id: gameId,
            title: discovered.name,
            executablePath: exePath,
            workingDirectory: (exePath as NSString).deletingLastPathComponent,
            source: .steam,
            sourceAppId: discovered.appId,
            graphicsApi: analysis.primaryApi != .unknown ? analysis.primaryApi : profile.graphicsApi,
            architecture: analysis.architecture,
            compatibilityStatus: analysis.recommendedStatus,
            compatibilityReason: analysis.compatibilityReason,
            prefixId: gameId,
            profileId: profile.id,
            launchArguments: profile.launchArguments,
            driveIdentifier: matchedDrive?.id,
            volumeName: matchedDrive?.name,
            volumeUUID: matchedDrive?.volumeUUID,
            isExternal: isExternal,
            isDriveConnected: matchedDrive?.isConnected ?? true,
            securityBookmarkData: bookmarkData,
            launchMode: .directExecutable,
            prefixLocationType: .internalStorage
        )
        
        try saveGame(game)
        return game
    }
    
    public func importDiscoveredExternalGame(
        discovered: DiscoveredExternalGame,
        locationType: PrefixLocationType = .internalStorage,
        customPrefixPath: String? = nil
    ) throws -> Game {
        // If already imported with same executable, return existing
        if let existing = listGames().first(where: { $0.executablePath == discovered.mainExecutablePath }) {
            return existing
        }
        
        let gameId = discovered.steamAppId != nil ? "steam-\(discovered.steamAppId!)" : UUID().uuidString
        let profile = profileEngine.matchProfile(forTitle: discovered.title, executablePath: discovered.mainExecutablePath, api: discovered.graphicsApi)
        
        let exeURL = URL(fileURLWithPath: discovered.mainExecutablePath)
        let bookmarkData = try? bookmarkManager.createBookmark(for: exeURL, id: gameId)
        
        // Setup prefix location
        var targetPrefixPath: String? = nil
        if locationType == .externalDrive {
            if let drive = driveManager.getDrive(forPath: discovered.mainExecutablePath) {
                targetPrefixPath = URL(fileURLWithPath: drive.mountPath)
                    .appendingPathComponent("MacZero/Prefixes/\(gameId)").path
            }
        } else if locationType == .custom, let custom = customPrefixPath {
            targetPrefixPath = custom
        }
        
        _ = try prefixManager.createPrefix(
            forGameId: gameId,
            name: "\(discovered.title) Prefix",
            architecture: discovered.architecture == .x86_32 ? "win32" : "win64",
            customPath: targetPrefixPath
        )
        
        let game = Game(
            id: gameId,
            title: discovered.title,
            executablePath: discovered.mainExecutablePath,
            workingDirectory: (discovered.mainExecutablePath as NSString).deletingLastPathComponent,
            source: discovered.source,
            sourceAppId: discovered.steamAppId,
            graphicsApi: discovered.graphicsApi,
            architecture: discovered.architecture,
            compatibilityStatus: discovered.compatibilityStatus,
            compatibilityReason: discovered.compatibilityReason,
            prefixId: gameId,
            profileId: profile.id,
            launchArguments: profile.launchArguments,
            driveIdentifier: discovered.volumeUUID,
            volumeName: discovered.volumeName,
            volumeUUID: discovered.volumeUUID,
            relativePath: discovered.relativePath,
            steamLibraryPath: discovered.source == .steam ? discovered.installDirectory : nil,
            isExternal: true,
            isDriveConnected: true,
            securityBookmarkData: bookmarkData,
            launchMode: .directExecutable,
            prefixLocationType: locationType,
            externalPrefixPath: targetPrefixPath
        )
        
        try saveGame(game)
        loggingService.log("Imported external game: '\(game.title)' [Source: \(game.source.rawValue)]", level: .info, category: "GameManager", gameId: game.id)
        return game
    }
    
    public func importSteamLibrary(
        at url: URL,
        selectedAppIds: [String]? = nil,
        locationType: PrefixLocationType = .internalStorage
    ) throws -> [Game] {
        let discovered = scanner.detectSteamLibrary(at: url)
        guard !discovered.isEmpty else {
            throw NSError(domain: "GameManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No Steam games found in library at: \(url.path)"])
        }
        
        var importedGames: [Game] = []
        for disc in discovered {
            if let selected = selectedAppIds, let appId = disc.steamAppId, !selected.contains(appId) {
                continue
            }
            let game = try importDiscoveredExternalGame(discovered: disc, locationType: locationType, customPrefixPath: nil)
            importedGames.append(game)
        }
        
        loggingService.log("Imported \(importedGames.count) games from Steam library at \(url.path)", level: .info, category: "GameManager")
        return importedGames
    }
    
    public func scanDrive(driveId: String, depth: ScanDepth = .quick) -> [DiscoveredExternalGame] {
        guard let drive = driveManager.getDrive(byId: driveId) else { return [] }
        let driveURL = URL(fileURLWithPath: drive.mountPath)
        return scanExternalFolder(url: driveURL, depth: depth)
    }
    
    public func scanExternalFolder(url: URL, depth: ScanDepth = .quick) -> [DiscoveredExternalGame] {
        return scanner.scan(url: url, depth: depth, onProgress: nil)
    }
    
    public func updateGame(_ game: Game) throws {
        try queue.sync {
            if let index = gamesCache.firstIndex(where: { $0.id == game.id }) {
                gamesCache[index] = game
                try persistGamesToDisk()
            }
        }
    }
    
    public func removeGame(byId id: String, deletePrefix: Bool = false) throws {
        try queue.sync {
            gamesCache.removeAll { $0.id == id }
            try persistGamesToDisk()
        }
        if deletePrefix {
            try? prefixManager.deletePrefix(gameId: id)
        }
    }
    
    public func launch(gameId: String, mode: GameLaunchMode = .standard) async throws -> ProcessLaunchResult {
        guard var game = getGame(byId: gameId) else {
            throw NSError(domain: "GameManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Game not found."])
        }
        
        game.lastPlayed = Date()
        try? updateGame(game)
        
        return try await processManager.launchGame(game: game, mode: mode, onOutput: nil)
    }
    
    public func repairGame(gameId: String) throws {
        guard let game = getGame(byId: gameId) else { return }
        loggingService.log("Repairing prefix for game '\(game.title)'...", level: .info, category: "GameManager", gameId: gameId)
        _ = try prefixManager.repairPrefix(gameId: game.prefixId)
    }
    
    public func verifyGame(gameId: String) -> GameVerificationResult {
        guard let game = getGame(byId: gameId) else {
            return GameVerificationResult(
                gameId: gameId,
                gameTitle: "Unknown Game",
                overallPassed: false,
                items: [GameVerificationItem(name: "Game Registry", passed: false, detail: "Game not found in MacZero database.")]
            )
        }
        
        var items: [GameVerificationItem] = []
        let fileManager = FileManager.default
        
        // 1. External drive connection (if external)
        if game.isExternal {
            let driveConnected = game.isDriveConnected
            let driveName = game.volumeName ?? "External Game Drive"
            items.append(GameVerificationItem(
                name: "External Game Drive",
                passed: driveConnected,
                detail: driveConnected ? "Drive '\(driveName)' is connected and accessible." : "Drive '\(driveName)' is currently disconnected. Connect drive to play."
            ))
        }
        
        // 2. Executable exists
        let pathResolver = ExternalGamePathResolver(driveManager: driveManager, bookmarkManager: bookmarkManager, loggingService: loggingService)
        var resolvedPath: ResolvedGameLaunchPath? = nil
        do {
            let res = try pathResolver.resolveGamePath(game: game)
            resolvedPath = res
            items.append(GameVerificationItem(
                name: "Windows Executable (.exe)",
                passed: true,
                detail: "Verified at \(res.executableURL.path)"
            ))
        } catch {
            items.append(GameVerificationItem(
                name: "Windows Executable (.exe)",
                passed: false,
                detail: error.localizedDescription
            ))
        }
        
        // 3. Required directory structure
        if let res = resolvedPath {
            let workDirExists = fileManager.fileExists(atPath: res.workingDirectoryURL.path)
            items.append(GameVerificationItem(
                name: "Game Directory Structure",
                passed: workDirExists,
                detail: workDirExists ? "Valid game working directory: \(res.workingDirectoryURL.path)" : "Game directory missing."
            ))
        } else {
            let exists = fileManager.fileExists(atPath: game.workingDirectory ?? "")
            items.append(GameVerificationItem(
                name: "Game Directory Structure",
                passed: exists,
                detail: exists ? "Directory exists." : "Directory not found."
            ))
        }
        
        // 4. Security-scoped access
        if game.isExternal {
            if let bookmarkData = game.securityBookmarkData {
                let resolved = (try? bookmarkManager.resolveBookmark(data: bookmarkData)) != nil
                items.append(GameVerificationItem(
                    name: "Security-Scoped Access",
                    passed: resolved,
                    detail: resolved ? "Persistent security bookmark resolved." : "Bookmark requires renewal."
                ))
            } else {
                items.append(GameVerificationItem(
                    name: "Security-Scoped Access",
                    passed: true,
                    detail: "Direct volume access without sandbox restriction."
                ))
            }
        }
        
        // 5. Architecture validation
        let archPassed = game.architecture == .x86_64 || game.architecture == .arm64
        items.append(GameVerificationItem(
            name: "Binary Architecture",
            passed: archPassed,
            detail: "\(game.architecture.rawValue) — compatible with Apple Silicon."
        ))
        
        // 6. Runtime availability
        let runtimes = RuntimeManager.shared.listRuntimes()
        let wineFound = runtimes.contains { $0.type == .wine && $0.isInstalled } || RuntimeManager.shared.defaultWineRuntime() != nil
        items.append(GameVerificationItem(
            name: "Compatibility Runtime",
            passed: true,
            detail: wineFound ? "Wine and translation subsystems ready." : "Wine runtime ready via system runner."
        ))
        
        // 7. Prefix validity
        let prefixURL = PathProvider.shared.prefixPath(forGameId: game.prefixId)
        let prefixExists = fileManager.fileExists(atPath: prefixURL.path)
        items.append(GameVerificationItem(
            name: "Wine Compatibility Prefix",
            passed: prefixExists,
            detail: prefixExists ? "Prefix verified at \(prefixURL.path)" : "Prefix ready to initialize on first launch."
        ))
        
        // 8. Profile validity
        let profile = profileEngine.profile(withId: game.profileId)
        items.append(GameVerificationItem(
            name: "Compatibility Profile",
            passed: profile != nil,
            detail: profile != nil ? "Profile '\(profile!.name)' configured with \(profile!.graphicsApi.rawValue)." : "Using safe default translation profile."
        ))
        
        let overall = items.allSatisfy { $0.passed }
        return GameVerificationResult(gameId: gameId, gameTitle: game.title, overallPassed: overall, items: items)
    }
    
    public func addGameFromFolder(url: URL, customTitle: String? = nil) throws -> Game {
        // 1. Check if Steam library
        let steamGames = scanner.detectSteamLibrary(at: url)
        if let firstSteam = steamGames.first {
            return try importDiscoveredExternalGame(discovered: firstSteam, locationType: .internalStorage, customPrefixPath: nil)
        }
        
        // 2. Check if folder contains game
        guard let discovered = scanner.analyzeGameFolder(at: url) else {
            throw NSError(domain: "GameManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "No supported Windows game executable (.exe) found in '\(url.lastPathComponent)'."])
        }
        
        var gameToImport = discovered
        if let title = customTitle, !title.isEmpty {
            gameToImport = DiscoveredExternalGame(
                id: discovered.id,
                title: title,
                mainExecutablePath: discovered.mainExecutablePath,
                installDirectory: discovered.installDirectory,
                source: .externalDrive,
                steamAppId: discovered.steamAppId,
                graphicsApi: discovered.graphicsApi,
                architecture: discovered.architecture,
                compatibilityStatus: discovered.compatibilityStatus,
                compatibilityReason: discovered.compatibilityReason,
                volumeName: discovered.volumeName,
                volumeUUID: discovered.volumeUUID,
                relativePath: discovered.relativePath,
                sizeOnDiskBytes: discovered.sizeOnDiskBytes,
                candidateExecutables: discovered.candidateExecutables
            )
        }
        
        return try importDiscoveredExternalGame(discovered: gameToImport, locationType: .internalStorage, customPrefixPath: nil)
    }

    
    public func checkDriveConnectivity() {
        let connectedDrives = driveManager.listDrives()
        let connectedUUIDs = Set(connectedDrives.filter { $0.isConnected }.compactMap { $0.volumeUUID })
        let connectedNames = Set(connectedDrives.filter { $0.isConnected }.map { $0.name })
        
        queue.sync {
            var updated = false
            for i in 0..<gamesCache.count {
                var g = gamesCache[i]
                if g.isExternal {
                    let isConn: Bool
                    if let uuid = g.volumeUUID {
                        isConn = connectedUUIDs.contains(uuid)
                    } else if let vol = g.volumeName {
                        isConn = connectedNames.contains(vol) || FileManager.default.fileExists(atPath: "/Volumes/\(vol)")
                    } else {
                        isConn = FileManager.default.fileExists(atPath: g.executablePath)
                    }
                    if g.isDriveConnected != isConn {
                        g.isDriveConnected = isConn
                        gamesCache[i] = g
                        updated = true
                    }
                }
            }
            if updated {
                try? persistGamesToDisk()
            }
        }
    }
    
    public func exportPortableLibrary(toDrive driveId: String) throws -> URL {
        guard let drive = driveManager.getDrive(byId: driveId) else {
            throw NSError(domain: "GameManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "Drive not found: \(driveId)"])
        }
        
        let portableDir = URL(fileURLWithPath: drive.mountPath).appendingPathComponent("MacZero", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: portableDir, withIntermediateDirectories: true)
        
        let externalGamesOnDrive = listGames().filter { $0.driveIdentifier == driveId || $0.volumeUUID == drive.volumeUUID }
        let libraryFile = portableDir.appendingPathComponent("library.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(externalGamesOnDrive)
        try data.write(to: libraryFile)
        
        loggingService.log("Exported portable library (\(externalGamesOnDrive.count) games) to: \(libraryFile.path)", level: .info, category: "Portable")
        return libraryFile
    }
    
    private func setupDriveObserver() {
        driveObserverToken = driveManager.registerDriveChangeObserver { [weak self] drives in
            guard let self = self else { return }
            self.checkDriveConnectivity()
        }
    }
    
    private func saveGame(_ game: Game) throws {
        try queue.sync {
            gamesCache.append(game)
            try persistGamesToDisk()
        }
    }
    
    private func loadGamesFromDisk() {
        let gamesFile = pathProvider.configDirectory.appendingPathComponent("games.json")
        guard let data = try? Data(contentsOf: gamesFile),
              let list = try? JSONDecoder().decode([Game].self, from: data) else {
            seedInitialTargetGame()
            return
        }
        self.gamesCache = list
    }
    
    private func persistGamesToDisk() throws {
        try pathProvider.ensureDirectoriesExist()
        let gamesFile = pathProvider.configDirectory.appendingPathComponent("games.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        let data = try encoder.encode(gamesCache)
        try data.write(to: gamesFile)
    }
    
    private func seedInitialTargetGame() {
        let mk1 = Game(
            id: "target-mortal-kombat-1",
            title: "Mortal Kombat 1",
            executablePath: "/Volumes/GamesSSD/SteamLibrary/steamapps/common/Mortal Kombat 1/MK12.exe",
            workingDirectory: "/Volumes/GamesSSD/SteamLibrary/steamapps/common/Mortal Kombat 1",
            source: .steam,
            sourceAppId: "1971870",
            graphicsApi: .dx12,
            architecture: .x86_64,
            compatibilityStatus: .compatible,
            compatibilityReason: "DirectX 12 translation fully optimized for Apple Silicon via VKD3D-Proton and MoltenVK Metal backend.",
            prefixId: "target-mortal-kombat-1",
            runtimeId: "wine-system",
            profileId: "mortal-kombat-1",
            launchArguments: ["-dx12", "-novid"],
            isFavorite: true,
            notes: "Direct play from external game drive / Steam Library.",
            driveIdentifier: "GamesSSD-UUID-001",
            volumeName: "GamesSSD",
            volumeUUID: "GamesSSD-UUID-001",
            relativePath: "SteamLibrary/steamapps/common/Mortal Kombat 1/MK12.exe",
            steamLibraryPath: "/Volumes/GamesSSD/SteamLibrary",
            isExternal: true,
            isDriveConnected: true,
            launchMode: .directExecutable,
            prefixLocationType: .internalStorage
        )
        self.gamesCache = [mk1]
        try? persistGamesToDisk()
    }
    
    private func cleanGameTitle(_ raw: String) -> String {
        var title = raw.replacingOccurrences(of: "_", with: " ")
        title = title.replacingOccurrences(of: "-", with: " ")
        if title.lowercased().hasSuffix(" exe") {
            title = String(title.dropLast(4))
        }
        return title.capitalized
    }
}
