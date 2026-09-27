import Foundation
import SwiftUI
import Combine
import MacGameCore

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public var games: [Game] = []
    @Published public var selectedGameId: String? = nil
    @Published public var filterCategory: SidebarCategory = .allGames
    @Published public var searchText: String = ""
    @Published public var isLaunching: Bool = false
    @Published public var activeLaunchPid: Int32? = nil
    @Published public var showAddGameWizard: Bool = false
    @Published public var showDiagnosticsSheet: Bool = false
    @Published public var showRuntimeSheet: Bool = false
    @Published public var showLogsSheet: Bool = false
    @Published public var lastLaunchError: String? = nil
    @Published public var lastLaunchResult: ProcessLaunchResult? = nil
    @Published public var showCrashAlert: Bool = false
    
    private let gameManager: GameManagerProtocol
    private let steamDetector: SteamDetector
    private let diagnosticsService: DiagnosticsServiceProtocol
    
    public enum SidebarCategory: String, CaseIterable, Identifiable {
        case allGames = "All Games"
        case favorites = "Favorites"
        case dx12Games = "DirectX 12"
        case steamGames = "Steam"
        case customGames = "Custom Windows .exe"
        
        public var id: String { rawValue }
        
        public var systemImage: String {
            switch self {
            case .allGames: return "gamecontroller.fill"
            case .favorites: return "star.fill"
            case .dx12Games: return "bolt.fill"
            case .steamGames: return "cloud.fill"
            case .customGames: return "terminal.fill"
            }
        }
    }
    
    public init(
        gameManager: GameManagerProtocol = GameManager.shared,
        steamDetector: SteamDetector = .shared,
        diagnosticsService: DiagnosticsServiceProtocol = DiagnosticsService.shared
    ) {
        self.gameManager = gameManager
        self.steamDetector = steamDetector
        self.diagnosticsService = diagnosticsService
        self.refreshGames()
        if self.selectedGameId == nil, let first = games.first {
            self.selectedGameId = first.id
        }
    }
    
    public var filteredGames: [Game] {
        return games.filter { game in
            let matchesCategory: Bool
            switch filterCategory {
            case .allGames:
                matchesCategory = true
            case .favorites:
                matchesCategory = game.isFavorite
            case .dx12Games:
                matchesCategory = game.graphicsApi == .dx12
            case .steamGames:
                matchesCategory = game.source == .steam
            case .customGames:
                matchesCategory = game.source == .customExe || game.source == .folder
            }
            
            if !matchesCategory { return false }
            
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                return game.title.lowercased().contains(query) ||
                       game.graphicsApi.rawValue.lowercased().contains(query)
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
}
