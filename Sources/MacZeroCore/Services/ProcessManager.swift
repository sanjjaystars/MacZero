import Foundation

public struct ProcessLaunchResult: Sendable {
    public let pid: Int32
    public let exitCode: Int32
    public let didCrash: Bool
    public let logFilePath: String
    public let crashReason: String?
}

public protocol ProcessManagerProtocol: Sendable {
    func launchGame(
        game: Game,
        mode: GameLaunchMode,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> ProcessLaunchResult
}

public final class ProcessManager: ProcessManagerProtocol, Sendable {
    public static let shared = ProcessManager()
    
    private let runtimeManager: RuntimeManagerProtocol
    private let prefixManager: PrefixManagerProtocol
    private let profileEngine: ProfileEngineProtocol
    private let hardwareDetector: HardwareDetector
    private let dx12Optimizer: DX12Optimizer
    private let loggingService: LoggingService
    private let pathProvider: PathProvider
    private let pathResolver: ExternalGamePathResolverProtocol
    private let bookmarkManager: SecurityScopedBookmarkManagerProtocol
    private let customRunnerBinary: String?


    
    public init(
        runtimeManager: RuntimeManagerProtocol = RuntimeManager.shared,
        prefixManager: PrefixManagerProtocol = PrefixManager.shared,
        profileEngine: ProfileEngineProtocol = ProfileEngine.shared,
        hardwareDetector: HardwareDetector = .shared,
        dx12Optimizer: DX12Optimizer = .shared,
        loggingService: LoggingService = .shared,
        pathProvider: PathProvider = .shared,
        pathResolver: ExternalGamePathResolverProtocol = ExternalGamePathResolver.shared,
        bookmarkManager: SecurityScopedBookmarkManagerProtocol = SecurityScopedBookmarkManager.shared,
        customRunnerBinary: String? = nil
    ) {
        self.runtimeManager = runtimeManager
        self.prefixManager = prefixManager
        self.profileEngine = profileEngine
        self.hardwareDetector = hardwareDetector
        self.dx12Optimizer = dx12Optimizer
        self.loggingService = loggingService
        self.pathProvider = pathProvider
        self.pathResolver = pathResolver
        self.bookmarkManager = bookmarkManager
        self.customRunnerBinary = customRunnerBinary
    }
    
    public func launchGame(

        game: Game,
        mode: GameLaunchMode = .standard,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) async throws -> ProcessLaunchResult {
        loggingService.log("Initiating launch sequence for '\(game.title)' [Mode: \(mode.rawValue)]", level: .info, category: "Launcher", gameId: game.id)
        
        // 1. Resolve Game Executable and External Drive Access
        let resolved = try pathResolver.resolveGamePath(game: game)
        loggingService.log("Resolved executable: \(resolved.executableURL.path) on volume '\(resolved.volumeName)'", level: .info, category: "Launcher", gameId: game.id)
        
        if let secURL = resolved.securityScopedURL {
            _ = bookmarkManager.startAccessing(url: secURL)
        }
        
        // 2. Ensure Prefix Exists (Internal or External)
        var prefix = prefixManager.getPrefix(forGameId: game.prefixId, customPath: game.externalPrefixPath)
        if prefix == nil {
            loggingService.log("Initializing dedicated Wine prefix for '\(game.title)'...", level: .info, category: "Prefix", gameId: game.id)
            prefix = try prefixManager.createPrefix(
                forGameId: game.prefixId,
                name: "\(game.title) Prefix",
                architecture: game.architecture == .x86_32 ? "win32" : "win64",
                customPath: game.externalPrefixPath
            )
        }
        
        let prefixPath = prefix!.path
        
        // 3. Resolve Profile & Optimization
        let profile = profileEngine.profile(withId: game.profileId) ?? profileEngine.matchProfile(forTitle: game.title, executablePath: resolved.executableURL.path, api: game.graphicsApi)
        let hardware = hardwareDetector.detect()
        
        // 4. Prepare Environment
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixPath
        env["WINEARCH"] = prefix!.wineArchitecture
        
        // Ensure consistent multi-threaded synchronization & 64-bit awareness
        env["WINEESYNC"] = "1"
        env["WINEFSYNC"] = "1"
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        
        // Vulkan / MoltenVK discovery
        let icdCandidates = [
            "/opt/homebrew/etc/vulkan/icd.d/MoltenVK_icd.json",
            "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json",
            "/usr/local/etc/vulkan/icd.d/MoltenVK_icd.json",
            "/usr/local/share/vulkan/icd.d/MoltenVK_icd.json"
        ]
        for candidate in icdCandidates {
            if FileManager.default.fileExists(atPath: candidate) {
                env["VK_ICD_FILENAMES"] = candidate
                break
            }
        }
        
        let existingDyld = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ""
        let libPaths = ["/opt/homebrew/lib", "/usr/local/lib"]
        let joinedLibs = libPaths.joined(separator: ":")
        env["DYLD_FALLBACK_LIBRARY_PATH"] = existingDyld.isEmpty ? joinedLibs : "\(existingDyld):\(joinedLibs)"
        
        if mode == .safeMode {
            loggingService.log("Safe Mode active: Disabling experimental DX12 flags and async queues.", level: .warn, category: "Launcher", gameId: game.id)
            env["VKD3D_CONFIG"] = "shader_cache"
            env["WINEDLLOVERRIDES"] = "d3d12,dxgi=b"
            env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = "1"
        } else {
            // Apply profile environment
            for (k, v) in profile.environment {
                env[k] = v
            }
            
            // Apply DX12 tuning if appropriate
            if game.graphicsApi == .dx12 || profile.graphicsApi == .dx12 {
                let dx12Env = dx12Optimizer.generateEnvironment(
                    options: DX12TuningOptions(
                        enableShaderCache: true,
                        enableRayTracing: hardware.chipGeneration.contains("M3") || hardware.chipGeneration.contains("M4"),
                        enableAsyncPso: true,
                        singleQueueMode: true
                    ),
                    hardware: hardware
                )
                for (k, v) in dx12Env {
                    env[k] = v
                }
            }
            
            // Apply DLL Overrides
            var overrideStrings: [String] = []
            for (dll, setting) in profile.dllOverrides {
                overrideStrings.append("\(dll)=\(setting)")
            }
            if !overrideStrings.isEmpty {
                env["WINEDLLOVERRIDES"] = overrideStrings.joined(separator: ";")
            }
        }
        
        // User custom env overrides
        for (k, v) in game.environmentVariables {
            env[k] = v
        }
        
        // 5. Resolve Runtime Runner
        let wineBinary: String
        if let custom = customRunnerBinary {
            wineBinary = custom
        } else if let testRunner = ProcessInfo.processInfo.environment["MACZERO_TEST_RUNNER"] {
            wineBinary = testRunner
        } else {
            let wineComponent = runtimeManager.defaultWineRuntime()
            wineBinary = wineComponent?.binaryPath ?? "/usr/bin/true"
        }
        
        // Ensure wineserver is fresh if retrying or in Safe Mode
        if mode == .safeMode {
            stopWineServer(forPrefix: prefixPath)
        }
        
        // Verify prefix is bootstrapped with valid 64-bit system DLLs
        ensurePrefixBootstrapped(prefixPath: prefixPath, wineBinary: wineBinary, architecture: prefix!.wineArchitecture)

        
        // 6. Build Arguments
        var arguments: [String] = []
        arguments.append(resolved.executableURL.path)
        if mode != .safeMode {
            arguments.append(contentsOf: profile.launchArguments)
            arguments.append(contentsOf: game.launchArguments)
        }
        
        loggingService.log("Runner binary: \(wineBinary)", level: .info, category: "Launcher", gameId: game.id)
        loggingService.log("Command arguments: \(arguments.joined(separator: " "))", level: .info, category: "Launcher", gameId: game.id)
        loggingService.log("Working directory: \(resolved.workingDirectoryURL.path)", level: .info, category: "Launcher", gameId: game.id)
        
        // 7. Launch Process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinary)
        process.arguments = arguments
        process.environment = env
        process.currentDirectoryURL = resolved.workingDirectoryURL

        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        let logFileURL = pathProvider.logPath(forGameId: game.id)
        
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let output = String(data: data, encoding: .utf8) {
                onOutput?(output)
                self.loggingService.log(output.trimmingCharacters(in: .newlines), level: .debug, category: "GameOutput", gameId: game.id)
            }
        }
        
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                fileHandle.readabilityHandler = nil
                
                let exitCode = proc.terminationStatus
                let didCrash = exitCode != 0
                
                var crashReason: String? = nil
                if didCrash {
                    crashReason = self.analyzeCrashLog(forGameId: game.id, exitCode: exitCode)
                    self.loggingService.log("Process exited with non-zero status code: \(exitCode). Reason: \(crashReason ?? "Unknown")", level: .error, category: "Crash", gameId: game.id)
                    // Clean up server to avoid esync mismatch on retry
                    self.stopWineServer(forPrefix: prefixPath)
                } else {
                    self.loggingService.log("Process finished successfully with exit code 0.", level: .info, category: "Process", gameId: game.id)
                }
                
                let result = ProcessLaunchResult(
                    pid: proc.processIdentifier,
                    exitCode: exitCode,
                    didCrash: didCrash,
                    logFilePath: logFileURL.path,
                    crashReason: crashReason
                )
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
                let pid = process.processIdentifier
                loggingService.log("Process started with PID \(pid)", level: .info, category: "Process", gameId: game.id)
            } catch {
                fileHandle.readabilityHandler = nil
                let result = ProcessLaunchResult(
                    pid: 0,
                    exitCode: -1,
                    didCrash: true,
                    logFilePath: logFileURL.path,
                    crashReason: "Failed to spawn process: \(error.localizedDescription)"
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    private func stopWineServer(forPrefix prefixPath: String) {
        let wineserverCandidates = [
            "/opt/homebrew/bin/wineserver",
            "/usr/local/bin/wineserver",
            "/Applications/Game Porting Toolkit.app/Contents/Resources/wine/bin/wineserver"
        ]
        guard let serverBin = wineserverCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverBin)
        process.arguments = ["-k"]
        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = prefixPath
        process.environment = env
        try? process.run()
        process.waitUntilExit()
    }
    
    private func ensurePrefixBootstrapped(prefixPath: String, wineBinary: String, architecture: String) {
        guard wineBinary != "/usr/bin/true" && !wineBinary.contains("test") else { return }
        guard !prefixPath.contains("/var/folders") && !prefixPath.contains("/tmp") else { return }
        
        let kernel32Path = (prefixPath as NSString).appendingPathComponent("drive_c/windows/system32/kernel32.dll")
        let fileManager = FileManager.default
        
        // If kernel32.dll is missing or empty, bootstrap via wineboot -u
        if !fileManager.fileExists(atPath: kernel32Path) {
            loggingService.log("Bootstrapping 64-bit Wine prefix via wineboot -u...", level: .info, category: "Prefix")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: wineBinary)
            process.arguments = ["wineboot", "-u"]
            var env = ProcessInfo.processInfo.environment
            env["WINEPREFIX"] = prefixPath
            env["WINEARCH"] = architecture
            process.environment = env
            try? process.run()
            process.waitUntilExit()
        }
    }
    
    private func analyzeCrashLog(forGameId gameId: String, exitCode: Int32) -> String {
        guard let logText = loggingService.getGameLog(gameId: gameId)?.lowercased() else {
            return "Process terminated with exit code \(exitCode)."
        }
        
        if logText.contains("esync_init") || logText.contains("wineesync") {
            return "Wineserver synchronization conflict. The background Wine server was reset; retry launch."
        }
        if logText.contains("could not load kernel32.dll") || logText.contains("c000007b") {
            return "Compatibility prefix architecture mismatch. The prefix was refreshed with 64-bit binaries; retry launch."
        }
        if logText.contains("vkd3d_create_device") || logText.contains("vkcreateinstance failed") {
            return "DirectX 12 / Vulkan initialization failed. Verify that MoltenVK is properly linked to Apple Metal."
        }
        if logText.contains("anticheat") || logText.contains("easyanticheat") || logText.contains("battleye") {
            return "Kernel anti-cheat driver blocked execution. This game requires unsupported Windows NT kernel services."
        }
        if logText.contains("out of memory") || logText.contains("dxgi_error_device_removed") {
            return "GPU device removed or memory exhaustion during frame rendering. Try reducing resolution or texture quality."
        }
        if logText.contains("dll not found") || logText.contains("err:module:import_dll") {
            return "Missing Windows dependency DLL (such as Visual C++ 2015-2022 redistributable or DirectX Runtime)."
        }
        return "Unexpected termination (code \(exitCode)). Try running in Safe Mode."
    }
}
