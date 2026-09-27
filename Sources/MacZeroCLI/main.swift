import Foundation
import MacZeroCore

@main
struct MacZeroCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count > 1 else {
            printUsage()
            return
        }
        
        let command = args[1].lowercased()
        let gameManager = GameManager.shared
        let driveManager = ExternalDriveManager.shared
        let runtimeManager = RuntimeManager.shared
        let prefixManager = PrefixManager.shared
        let diagnosticsService = DiagnosticsService.shared
        let steamDetector = SteamDetector.shared
        let loggingService = LoggingService.shared
        
        switch command {
        case "list":
            let games = gameManager.listGames()
            if games.isEmpty {
                print("No games installed. Use 'maczero install <path-to-exe>' or 'maczero scan' to add games.")
            } else {
                print("=== MacZero Library ===")
                for g in games {
                    let loc = g.isExternal ? "External: \(g.volumeName ?? "Drive")" : "Internal"
                    let driveStatus = g.isExternal ? (g.isDriveConnected ? "🟢 Connected" : "⚠ Disconnected") : ""
                    print("• [\(g.id)] \(g.title)")
                    print("  Status: \(g.compatibilityStatus.badgeText) | API: \(g.graphicsApi.rawValue) | Storage: \(loc) \(driveStatus)")
                    print("  Executable: \(g.executablePath)")
                }
            }
            
        case "drives":
            let drives = driveManager.refreshDrives()
            if drives.isEmpty {
                print("No external drives detected.")
            } else {
                print("=== External Game Drives ===")
                for d in drives {
                    let status = d.isConnected ? "🟢 Connected" : "⚠ Disconnected"
                    let ro = d.isReadOnly ? " [Read-Only]" : ""
                    print("• \(d.name) (\(status)\(ro))")
                    print("  Mount: \(d.mountPath)")
                    print("  Filesystem: \(d.fileSystemType) | UUID: \(d.volumeUUID ?? "N/A")")
                    print("  Capacity: \(d.formattedUsedCapacity) used / \(d.formattedTotalCapacity) total (\(d.formattedFreeCapacity) free)")
                    if let bench = d.benchmark {
                        print("  Performance: Read \(bench.formattedRead) | Write \(bench.formattedWrite)")
                    }
                }
            }
            
        case "scan-drive":
            guard args.count > 2 else {
                print("Usage: maczero scan-drive <path-or-drive-id> [--deep]")
                return
            }
            let target = args[2]
            let isDeep = args.contains("--deep")
            let depth: ScanDepth = isDeep ? .deep : .quick
            
            print("Scanning '\(target)' (\(depth.rawValue))...")
            let results: [DiscoveredExternalGame]
            if let drive = driveManager.getDrive(byId: target) {
                results = gameManager.scanDrive(driveId: drive.id, depth: depth)
            } else {
                let url = URL(fileURLWithPath: target)
                results = gameManager.scanExternalFolder(url: url, depth: depth)
            }
            
            if results.isEmpty {
                print("No Windows games or Steam libraries found at '\(target)'.")
            } else {
                print("Found \(results.count) game(s):")
                for r in results {
                    print("• \(r.title) [\(r.source.rawValue)]")
                    print("  Executable: \(r.mainExecutablePath)")
                    print("  API: \(r.graphicsApi.rawValue) | Architecture: \(r.architecture.rawValue)")
                }
            }
            
        case "import-steam":
            guard args.count > 2 else {
                print("Usage: maczero import-steam <path-to-steamlibrary-or-steamapps>")
                return
            }
            let path = args[2]
            let url = URL(fileURLWithPath: path)
            print("Importing Steam library at '\(path)'...")
            do {
                let imported = try gameManager.importSteamLibrary(at: url, selectedAppIds: nil, locationType: .internalStorage)
                print("✓ Successfully imported \(imported.count) Steam game(s):")
                for g in imported {
                    print("  • \(g.title) (AppID: \(g.sourceAppId ?? "N/A"))")
                }
            } catch {
                print("Error importing Steam library: \(error.localizedDescription)")
            }
            
        case "import-game":
            guard args.count > 2 else {
                print("Usage: maczero import-game <path-to-folder>")
                return
            }
            let path = args[2]
            let url = URL(fileURLWithPath: path)
            print("Analyzing game folder at '\(path)'...")
            if let discovered = GameFolderScanner.shared.analyzeGameFolder(at: url) {
                do {
                    let game = try gameManager.importDiscoveredExternalGame(discovered: discovered, locationType: .internalStorage, customPrefixPath: nil)
                    print("✓ Successfully imported game:")
                    print("  Title: \(game.title)")
                    print("  Executable: \(game.executablePath)")
                    print("  API: \(game.graphicsApi.rawValue)")
                } catch {
                    print("Error importing game: \(error.localizedDescription)")
                }
            } else {
                print("No candidate Windows executable (.exe) found in folder.")
            }
            
        case "bench":
            guard args.count > 2 else {
                print("Usage: maczero bench <drive-id>")
                return
            }
            let driveId = args[2]
            print("Benchmarking drive '\(driveId)'...")
            do {
                let result = try await driveManager.benchmarkDrive(id: driveId)
                print("✓ Benchmark results for drive '\(driveId)':")
                print("  Sequential Read:  \(result.formattedRead)")
                print("  Sequential Write: \(result.formattedWrite)")
            } catch {
                print("Benchmark failed: \(error.localizedDescription)")
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
                print("Usage: maczero install <path-to-exe> [game-title]")
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
                print("Usage: maczero launch <game-id-or-title> [--safe-mode]")
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
                    print("  Check logs with: maczero logs \(game.id)")
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
            
            print("=== MacZero System Diagnostics ===")
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
                print("Usage: maczero prefix <repair|reset|delete|list> <game-id>")
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
                print("Usage: maczero logs <game-id>")
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
        MacZero — Play your Windows games on Mac
        
        Usage: maczero <command> [options]
        
        Commands:
          list                                List all games in library
          drives                              List all mounted & known external game drives
          scan-drive <path-or-id> [--deep]   Scan external drive for games & Steam libraries
          import-steam <path>                 Import external Steam library directly
          import-game <path>                  Import external Windows game directory
          bench <drive-id>                    Test drive read and write performance
          scan                                Scan local Steam directories for games
          install <path-to-exe> [title]       Add a Windows executable to the library
          launch <game-id> [--safe-mode]      Launch game in standard or safe mode
          diagnose [game-id]                  Run diagnostics on system, runtime & game
          runtime list                        List discovered Wine, VKD3D, MoltenVK runtimes
          prefix repair <game-id>             Repair game prefix
          logs <game-id>                      View execution logs for a game
        """)
    }
}
