import Foundation
import SwiftUI
import Combine
import MacZeroCore

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var games: [Game] = []
    @Published public var drives: [ExternalDrive] = []
    @Published public var selectedGameId: String? = nil
    @Published public var filterCategory: SidebarCategory = .allGames
    @Published public var searchText: String = ""
    @Published public var isLaunching: Bool = false
    @Published public var activeLaunchPid: Int32? = nil
    @Published public var showAddGameWizard: Bool = false
    @Published public var showDiagnosticsSheet: Bool = false
    @Published public var showRuntimeSheet: Bool = false
    @Published public var showLogsSheet: Bool = false
    @Published public var showGameDrivesSheet: Bool = false
    @Published public var showExternalImportSheet: Bool = false
    @Published public var lastLaunchError: String? = nil
    @Published public var lastLaunchResult: ProcessLaunchResult? = nil
    @Published public var showCrashAlert: Bool = false
    @Published public var isBenchmarkingDrive: Bool = false
    @Published public var driveBenchmarkMessage: String? = nil
    @Published public var showVerificationSheet: Bool = false
    @Published public var verificationResult: GameVerificationResult? = nil
    @Published public var isScanningDrive: Bool = false
    @Published public var scanDriveMessage: String? = nil
    @Published public var droppedFolderURL: URL? = nil
    
    private let gameManager: GameManagerProtocol
    private let driveManager: ExternalDriveManagerProtocol
    private let steamDetector: SteamDetector
    private let diagnosticsService: DiagnosticsServiceProtocol
    private var driveObserverToken: UUID?
    
    public enum SidebarCategory: String, CaseIterable, Identifiable {
        case allGames = "All Games"
        case readyGames = "Ready to Play"
        case externalGames = "External Drives"
        case steamGames = "Steam Libraries"
        case internalGames = "Internal SSD"
        case favorites = "Favorites"
        case dx12Games = "DirectX 12"
        case customGames = "Custom Windows .exe"
        
        public var id: String { rawValue }
        
        public var systemImage: String {
            switch self {
            case .allGames: return "gamecontroller.fill"
            case .readyGames: return "checkmark.circle.fill"
            case .externalGames: return "externaldrive.fill"
            case .internalGames: return "internaldrive.fill"
            case .steamGames: return "cloud.fill"
            case .favorites: return "star.fill"
            case .dx12Games: return "bolt.fill"
            case .customGames: return "terminal.fill"
            }
        }
    }
    
    public init(
        gameManager: GameManagerProtocol = GameManager.shared,
        driveManager: ExternalDriveManagerProtocol = ExternalDriveManager.shared,
        steamDetector: SteamDetector = .shared,
        diagnosticsService: DiagnosticsServiceProtocol = DiagnosticsService.shared
    ) {
        self.gameManager = gameManager
        self.driveManager = driveManager
        self.steamDetector = steamDetector
        self.diagnosticsService = diagnosticsService
        
        self.refreshGames()
        self.refreshDrives()
        
        if self.selectedGameId == nil, let first = games.first {
            self.selectedGameId = first.id
        }
        
        self.driveObserverToken = driveManager.registerDriveChangeObserver { [weak self] updatedDrives in
            Task { @MainActor in
                self?.drives = updatedDrives
                self?.refreshGames()
            }
        }
    }
    
    deinit {
        if let token = driveObserverToken {
            driveManager.unregisterDriveChangeObserver(id: token)
        }
    }
    
    public var filteredGames: [Game] {
        return games.filter { game in
            let matchesCategory: Bool
            switch filterCategory {
            case .allGames:
                matchesCategory = true
            case .readyGames:
                matchesCategory = game.isReady
            case .externalGames:
                matchesCategory = game.isExternal
            case .internalGames:
                matchesCategory = !game.isExternal
            case .steamGames:
                matchesCategory = game.source == .steam
            case .favorites:
                matchesCategory = game.isFavorite
            case .dx12Games:
                matchesCategory = game.graphicsApi == .dx12
            case .customGames:
                matchesCategory = game.source == .customExe || game.source == .folder
            }
            
            if !matchesCategory { return false }
            
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return game.title.lowercased().contains(query) ||
                       game.graphicsApi.rawValue.lowercased().contains(query) ||
                       (game.volumeName?.lowercased().contains(query) ?? false)
            }
            return true
        }
    }
    
    public var selectedGame: Game? {
        guard let id = selectedGameId else { return nil }
        return games.first { $0.id == id }
    }
    
    public func refreshGames() {
        self.games = gameManager.listGames()
    }
    
    public func refreshDrives() {
        self.drives = driveManager.refreshDrives()
    }
    
    public func selectGame(id: String) {
        self.selectedGameId = id
    }
    
    public func toggleFavorite(gameId: String) {
        guard var g = games.first(where: { $0.id == gameId }) else { return }
        g.isFavorite.toggle()
        try? gameManager.updateGame(g)
        refreshGames()
    }
    
    public func launchSelectedGame(mode: GameLaunchMode = .standard) {
        guard let game = selectedGame else { return }
        
        // Check drive connection
        if game.isExternal && !game.isDriveConnected {
            self.lastLaunchError = "External game drive '\(game.volumeName ?? "Drive")' is disconnected. Please connect the drive to launch."
            self.showCrashAlert = true
            return
        }
        
        isLaunching = true
        lastLaunchError = nil
        lastLaunchResult = nil
        
        Task {
            do {
                let result = try await gameManager.launch(gameId: game.id, mode: mode)
                self.lastLaunchResult = result
                self.isLaunching = false
                self.refreshGames()
                
                if result.didCrash {
                    self.showCrashAlert = true
                }
            } catch {
                self.isLaunching = false
                self.lastLaunchError = error.localizedDescription
                self.showCrashAlert = true
            }
        }
    }
    
    public func repairSelectedGame() {
        guard let game = selectedGame else { return }
        try? gameManager.repairGame(gameId: game.id)
        refreshGames()
    }
    
    public func removeSelectedGame(deletePrefix: Bool = false) {
        guard let game = selectedGame else { return }
        try? gameManager.removeGame(byId: game.id, deletePrefix: deletePrefix)
        self.selectedGameId = nil
        refreshGames()
        if let first = games.first {
            self.selectedGameId = first.id
        }
    }
    
    public func benchmarkDrive(id: String) {
        isBenchmarkingDrive = true
        driveBenchmarkMessage = "Measuring drive read and write performance..."
        Task {
            do {
                let res = try await driveManager.benchmarkDrive(id: id)
                self.isBenchmarkingDrive = false
                self.driveBenchmarkMessage = "Benchmark complete! Read: \(res.formattedRead) | Write: \(res.formattedWrite)"
                self.refreshDrives()
            } catch {
                self.isBenchmarkingDrive = false
                self.driveBenchmarkMessage = "Benchmark failed: \(error.localizedDescription)"
            }
        }
    }
    
    public func removeDrive(id: String) {
        driveManager.removeDrive(id: id)
        refreshDrives()
    }
    
    public func verifySelectedGame() {
        guard let id = selectedGameId else { return }
        self.verificationResult = gameManager.verifyGame(gameId: id)
        self.showVerificationSheet = true
    }
    
    public func handleDroppedURLs(_ urls: [URL]) {
        guard let url = urls.first else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                self.droppedFolderURL = url
                self.showExternalImportSheet = true
            } else if url.pathExtension.lowercased() == "exe" {
                self.showAddGameWizard = true
            }
        }
    }
    
    public func quickScanDrive(drive: ExternalDrive) {
        isScanningDrive = true
        scanDriveMessage = "Scanning '\(drive.name)' for Windows games..."
        Task {
            let discovered = gameManager.scanDrive(driveId: drive.id, depth: .quick)
            for disc in discovered {
                _ = try? gameManager.importDiscoveredExternalGame(discovered: disc, locationType: .internalStorage, customPrefixPath: nil)
            }
            self.isScanningDrive = false
            self.scanDriveMessage = "Registered \(discovered.count) game(s) from '\(drive.name)'."
            self.refreshGames()
            self.refreshDrives()
        }
    }
}
