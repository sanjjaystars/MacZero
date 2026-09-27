import Foundation

public protocol GameManagerProtocol: Sendable {
    func listGames() -> [Game]
    func getGame(byId id: String) -> Game?
    func addGameFromExecutable(path: String, customTitle: String?, source: GameSource) throws -> Game
    func importSteamGame(discovered: DiscoveredSteamGame) throws -> Game
    func updateGame(_ game: Game) throws
    func removeGame(byId id: String, deletePrefix: Bool) throws
    func launch(gameId: String, mode: GameLaunchMode) async throws -> ProcessLaunchResult
    func repairGame(gameId: String) throws
}

public final class GameManager: GameManagerProtocol, @unchecked Sendable {
    public static let shared = GameManager()
    
    private let pathProvider: PathProvider
    private let binaryInspector: BinaryInspector
    private let profileEngine: ProfileEngineProtocol
    private let prefixManager: PrefixManagerProtocol
    private let processManager: ProcessManagerProtocol
    private let loggingService: LoggingService
    
    private var gamesCache: [Game] = []
    private let queue = DispatchQueue(label: "com.macgame.gamemanager")
    
    public init(
        pathProvider: PathProvider = .shared,
        binaryInspector: BinaryInspector = .shared,
        profileEngine: ProfileEngineProtocol = ProfileEngine.shared,
        prefixManager: PrefixManagerProtocol = PrefixManager.shared,
        processManager: ProcessManagerProtocol = ProcessManager.shared,
        loggingService: LoggingService = .shared
    ) {
        self.pathProvider = pathProvider
        self.binaryInspector = binaryInspector
        self.profileEngine = profileEngine
        self.prefixManager = prefixManager
        self.processManager = processManager
        self.loggingService = loggingService
        
        loadGamesFromDisk()
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
        
        // 3. Create isolated prefix
        let gameId = UUID().uuidString
        _ = try prefixManager.createPrefix(forGameId: gameId, name: "\(sanitizedTitle) Prefix", architecture: analysis.architecture == .x86_32 ? "win32" : "win64")
        
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
            environmentVariables: [:]
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
        
        // If already registered, return existing
        if let existing = getGame(byId: gameId) {
            return existing
        }
        
        let analysis = binaryInspector.inspect(executablePath: exePath)
        let profile = profileEngine.matchProfile(forTitle: discovered.name, executablePath: exePath, api: analysis.primaryApi)
        
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
            launchArguments: profile.launchArguments
        )
        
        try saveGame(game)
        return game
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
            // Seed sample target game Mortal Kombat 1 if library is completely empty
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
        // Pre-configure Mortal Kombat 1 as the first target game reference
        let mk1 = Game(
            id: "target-mortal-kombat-1",
            title: "Mortal Kombat 1",
            executablePath: "/Users/Shared/Games/MortalKombat1/MK12.exe",
            workingDirectory: "/Users/Shared/Games/MortalKombat1",
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
            notes: "First milestone target game. Single-player and local fight modes run smoothly at 60 FPS."
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
