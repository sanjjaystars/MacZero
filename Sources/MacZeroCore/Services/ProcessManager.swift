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
        
        try process.run()
        let pid = process.processIdentifier
        loggingService.log("Process started with PID \(pid)", level: .info, category: "Process", gameId: game.id)
        
        // Handle stream output asynchronously
        let fileHandle = pipe.fileHandleForReading
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                onOutput?(output)
                self.loggingService.log(output.trimmingCharacters(in: .newlines), level: .debug, category: "GameOutput", gameId: game.id)
            }
        }
        
        // Wait for process in background without blocking main thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                fileHandle.readabilityHandler = nil
                
                let exitCode = process.terminationStatus
                let didCrash = exitCode != 0
                
                var crashReason: String? = nil
                if didCrash {
                    crashReason = self.analyzeCrashLog(forGameId: game.id, exitCode: exitCode)
                    self.loggingService.log("Process exited with non-zero status code: \(exitCode). Reason: \(crashReason ?? "Unknown")", level: .error, category: "Crash", gameId: game.id)
                } else {
                    self.loggingService.log("Process finished successfully with exit code 0.", level: .info, category: "Process", gameId: game.id)
                }
                
                let result = ProcessLaunchResult(
                    pid: pid,
                    exitCode: exitCode,
                    didCrash: didCrash,
                    logFilePath: logFileURL.path,
                    crashReason: crashReason
                )
                continuation.resume(returning: result)
            }
        }
    }
    
    private func analyzeCrashLog(forGameId gameId: String, exitCode: Int32) -> String {
        guard let logText = loggingService.getGameLog(gameId: gameId)?.lowercased() else {
            return "Process terminated with exit code \(exitCode)."
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
