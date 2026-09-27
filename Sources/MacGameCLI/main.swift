import Foundation
import MacGameCore

@main
struct MacGameCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            printUsage()
            return
        }
        
        let command = args[1].lowercased()
        let gameManager = GameManager.shared
        let runtimeManager = RuntimeManager.shared
        let prefixManager = PrefixManager.shared
        let diagnosticsService = DiagnosticsService.shared
        let steamDetector = SteamDetector.shared
        let loggingService = LoggingService.shared
        
        switch command {
        case "list":
            let games = gameManager.listGames()
            if games.isEmpty {
                print("No games installed. Use 'macgame install <path-to-exe>' or 'macgame scan' to add games.")
            } else {
                print("=== MacGame Library ===")
                for g in games {
                    print("• [\(g.id)] \(g.title)")
                    print("  Status: \(g.compatibilityStatus.badgeText) | API: \(g.graphicsApi.rawValue) | Arch: \(g.architecture.rawValue)")
                    print("  Executable: \(g.executablePath)")
                }
            }
            
        case "scan":
            print("Scanning for installed Windows games via Steam and standard directories...")
            let steamGames = steamDetector.scanSteamLibraries()
            if steamGames.isEmpty {
                print("No Steam games detected in local library.")
            } else {
                print("Found \(steamGames.count) Steam game(s):")
                for s in steamGames {
                    let versionType = s.isWindowsVersion ? "Windows (.exe)" : (s.isNativeMacVersion ? "Native Mac (.app)" : "Unknown")
                    print("• [AppID: \(s.appId)] \(s.name) (\(versionType))")
                    if let exe = s.executablePath {
                        print("  Detected Exe: \(exe)")
                    }
                }
            }
            
        case "install":
            guard args.count > 2 else {
                print("Usage: macgame install <path-to-exe> [game-title]")
                return
            }
            let exePath = args[2]
            let customTitle = args.count > 3 ? args[3] : nil
            do {
                let game = try gameManager.addGameFromExecutable(path: exePath, customTitle: customTitle, source: .customExe)
                print("✓ Successfully installed game:")
                print("  Title: \(game.title)")
                print("  ID: \(game.id)")
                print("  Status: \(game.compatibilityStatus.badgeText)")
                print("  Graphics API: \(game.graphicsApi.rawValue)")
                print("  Prefix initialized at: \(PathProvider.shared.prefixPath(forGameId: game.prefixId).path)")
            } catch {
                print("Error installing game: \(error.localizedDescription)")
            }
            
        case "launch":
            guard args.count > 2 else {
                print("Usage: macgame launch <game-id-or-title> [--safe-mode]")
                return
            }
            let identifier = args[2]
            let isSafeMode = args.contains("--safe-mode")
            guard let game = gameManager.listGames().first(where: { $0.id == identifier || $0.title.lowercased() == identifier.lowercased() }) else {
                print("Game '\(identifier)' not found in library.")
                return
            }
            
            print("Launching '\(game.title)' [Mode: \(isSafeMode ? "Safe Mode" : "Standard")]...")
            do {
                let result = try await gameManager.launch(gameId: game.id, mode: isSafeMode ? .safeMode : .standard)
                if result.didCrash {
                    print("⚠️ Game exited with error code \(result.exitCode)")
                    if let reason = result.crashReason {
                        print("  Reason: \(reason)")
                    }
                    print("  Check logs with: macgame logs \(game.id)")
                } else {
                    print("✓ Game execution completed successfully.")
                }
            } catch {
                print("Failed to launch game: \(error.localizedDescription)")
            }
            
        case "diagnose":
            let gameIdentifier = args.count > 2 ? args[2] : nil
            let game = gameIdentifier.flatMap { id in
                gameManager.listGames().first(where: { $0.id == id || $0.title.lowercased() == id.lowercased() })
            }
            
            print("=== MacGame System Diagnostics ===")
            let report = diagnosticsService.runSystemDiagnostics(forGame: game)
            print("Hardware: \(report.hardwareSummary.chipName) (\(report.hardwareSummary.chipGeneration))")
            print("Memory: \(report.hardwareSummary.unifiedMemoryGB) GB Unified Memory")
            print("Metal: \(report.hardwareSummary.metalDeviceName) [\(report.hardwareSummary.metalFeatureSet)]")
            print("\nCheck Results:")
            for item in report.items {
                let icon = item.passed ? "✓" : "✗"
                print("[\(icon)] \(item.title): \(item.message)")
                if let details = item.details {
                    print("    Details: \(details)")
                }
                if let rem = item.remediationSuggestion {
                    print("    👉 Recommendation: \(rem)")
                }
            }
            print("\nOverall: \(report.summaryMessage)")
            
        case "runtime":
            let runtimes = runtimeManager.listRuntimes()
            print("=== Available Compatibility Runtimes ===")
            for r in runtimes {
                let status = r.isInstalled ? "Installed" : "Not Found"
                let def = r.isDefault ? "(Default)" : ""
                print("• [\(r.type.rawValue)] \(r.name) \(def)")
                print("  Version: \(r.version) | Arch: \(r.architecture.rawValue) | Status: \(status)")
                if let lib = r.libraryPath {
                    print("  Library: \(lib)")
                }
                if let bin = r.binaryPath {
                    print("  Binary: \(bin)")
                }
            }
            
        case "prefix":
            guard args.count > 3 else {
                print("Usage: macgame prefix <repair|reset|delete|list> <game-id>")
                return
            }
            let sub = args[2].lowercased()
            let gameId = args[3]
            
            do {
                if sub == "repair" {
                    _ = try prefixManager.repairPrefix(gameId: gameId)
                    print("✓ Prefix for '\(gameId)' repaired.")
                } else if sub == "reset" {
                    _ = try prefixManager.resetPrefix(gameId: gameId)
                    print("✓ Prefix for '\(gameId)' reset to factory state.")
                } else if sub == "delete" {
                    try prefixManager.deletePrefix(gameId: gameId)
                    print("✓ Prefix for '\(gameId)' deleted.")
                }
            } catch {
                print("Prefix operation failed: \(error.localizedDescription)")
            }
            
        case "logs":
            guard args.count > 2 else {
                print("Usage: macgame logs <game-id>")
                return
            }
            let gid = args[2]
            if let log = loggingService.getGameLog(gameId: gid) {
                print(log)
            } else {
                print("No log file found for game ID '\(gid)'.")
            }
            
        default:
            print("Unknown command: \(command)")
            printUsage()
        }
    }
    
    static func printUsage() {
        print("""
        MacGame — Play your Windows games on Mac
        
        Usage: macgame <command> [options]
        
        Commands:
          list                          List all games in library
          scan                          Scan Steam and standard directories for games
          install <path-to-exe> [title] Add a Windows executable to the library
          launch <game-id> [--safe-mode] Launch game in standard or safe mode
          diagnose [game-id]            Run diagnostics on system, runtime & game
          runtime list                  List discovered Wine, VKD3D, MoltenVK runtimes
          prefix repair <game-id>       Repair game prefix
          logs <game-id>                View execution logs for a game
        """)
    }
}
