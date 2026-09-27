import Foundation

public protocol DiagnosticsServiceProtocol: Sendable {
    func runSystemDiagnostics(forGame: Game?) -> DiagnosticReport
}

public final class DiagnosticsService: DiagnosticsServiceProtocol, Sendable {
    public static let shared = DiagnosticsService()
    
    private let hardwareDetector: HardwareDetector
    private let runtimeManager: RuntimeManagerProtocol
    private let prefixManager: PrefixManagerProtocol
    private let pathProvider: PathProvider
    
    public init(
        hardwareDetector: HardwareDetector = .shared,
        runtimeManager: RuntimeManagerProtocol = RuntimeManager.shared,
        prefixManager: PrefixManagerProtocol = PrefixManager.shared,
        pathProvider: PathProvider = .shared
    ) {
        self.hardwareDetector = hardwareDetector
        self.runtimeManager = runtimeManager
        self.prefixManager = prefixManager
        self.pathProvider = pathProvider
    }
    
    public func runSystemDiagnostics(forGame game: Game? = nil) -> DiagnosticReport {
        let hardware = hardwareDetector.detect()
        var items: [DiagnosticCheckItem] = []
        
        // 1. Apple Silicon Check
        let isAppleSilicon = !hardware.chipGeneration.isEmpty && hardware.chipGeneration != "Unknown"
        items.append(DiagnosticCheckItem(
            category: "Hardware",
            title: "Apple Silicon Architecture",
            passed: isAppleSilicon,
            severity: isAppleSilicon ? .success : .error,
            message: "Detected: \(hardware.chipName) (\(hardware.chipGeneration)) with \(hardware.cpuCores) CPU cores.",
            details: "Optimized for unified memory and Apple GPU execution.",
            remediationSuggestion: isAppleSilicon ? nil : "MacGame requires an Apple Silicon (M1-M5) Mac."
        ))
        
        // 2. macOS Version Check
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let isModernMacOS = os.majorVersion >= 14
        items.append(DiagnosticCheckItem(
            category: "System",
            title: "macOS Version",
            passed: isModernMacOS,
            severity: isModernMacOS ? .success : .warning,
            message: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            details: "DirectX 12 translation performs best on macOS Sonoma 14.0 or newer.",
            remediationSuggestion: isModernMacOS ? nil : "Upgrade to macOS 14 (Sonoma) or newer for optimal Metal 3 performance."
        ))
        
        // 3. Metal 3 & Ray Tracing Support
        let metalPassed = !hardware.metalDeviceName.contains("Unknown")
        items.append(DiagnosticCheckItem(
            category: "Graphics",
            title: "Metal Graphics Acceleration",
            passed: metalPassed,
            severity: metalPassed ? .success : .error,
            message: "\(hardware.metalDeviceName) [\(hardware.metalFeatureSet)]",
            details: "MoltenVK translates Vulkan and DirectX 12 calls directly into Metal 3 command buffers.",
            remediationSuggestion: metalPassed ? nil : "No Metal-compatible GPU found."
        ))
        
        // 4. Unified Memory Check
        let memGB = hardware.unifiedMemoryGB
        let memPassed = memGB >= 8
        items.append(DiagnosticCheckItem(
            category: "Hardware",
            title: "Unified Memory",
            passed: memPassed,
            severity: memPassed ? (memGB >= 16 ? .success : .info) : .warning,
            message: "\(memGB) GB Unified Memory",
            details: memGB >= 16 ? "Ideal for high-resolution textures and DX12 shader cache." : "Meets minimum requirements; 16GB+ recommended for modern DX12 AAA titles.",
            remediationSuggestion: memPassed ? nil : "Close background memory-heavy apps before launching modern titles."
        ))
        
        // 5. MoltenVK Translation Layer Check
        let molten = runtimeManager.defaultVulkanRuntime()
        let moltenInstalled = molten?.isInstalled ?? false
        items.append(DiagnosticCheckItem(
            category: "Runtime",
            title: "MoltenVK Vulkan Translation",
            passed: moltenInstalled,
            severity: moltenInstalled ? .success : .warning,
            message: moltenInstalled ? "MoltenVK available at \(molten?.libraryPath ?? "system")" : "MoltenVK not found in standard paths",
            details: "Required to bridge Vulkan/VKD3D to Apple Metal.",
            remediationSuggestion: moltenInstalled ? nil : "Install molten-vk via Homebrew (`brew install molten-vk`) or MacGame Runtime Manager."
        ))
        
        // 6. Wine Execution Runner Check
        let wine = runtimeManager.defaultWineRuntime()
        let wineInstalled = wine?.isInstalled ?? false
        items.append(DiagnosticCheckItem(
            category: "Runtime",
            title: "Wine / Windows Subsystem",
            passed: wineInstalled,
            severity: wineInstalled ? .success : .warning,
            message: wineInstalled ? "Wine runner ready: \(wine?.name ?? "")" : "Wine runner not detected",
            details: wine?.releaseNotes,
            remediationSuggestion: wineInstalled ? nil : "Install Wine via Homebrew (`brew install --cask wine-staging`) or configure a runner in Runtime Manager."
        ))
        
        // 7. Rosetta 2 Check
        items.append(DiagnosticCheckItem(
            category: "System",
            title: "Rosetta 2 Subsystem",
            passed: hardware.isRosettaActiveOrAvailable,
            severity: hardware.isRosettaActiveOrAvailable ? .success : .info,
            message: hardware.isRosettaActiveOrAvailable ? "Rosetta 2 available for x86_64 translation" : "Rosetta 2 translation layer not installed",
            details: "Required for running 64-bit Intel Windows binaries on Apple Silicon.",
            remediationSuggestion: hardware.isRosettaActiveOrAvailable ? nil : "Run `softwareupdate --install-rosetta` in Terminal to install Rosetta 2."
        ))
        
        // 8. If a specific Game is being checked
        if let g = game {
            // Executable existence
            let exeExists = FileManager.default.fileExists(atPath: g.executablePath)
            items.append(DiagnosticCheckItem(
                category: "Game",
                title: "Game Executable",
                passed: exeExists,
                severity: exeExists ? .success : .error,
                message: exeExists ? "Executable found: \((g.executablePath as NSString).lastPathComponent)" : "File missing at: \(g.executablePath)",
                details: "Graphics API: \(g.graphicsApi.rawValue) | Architecture: \(g.architecture.rawValue)",
                remediationSuggestion: exeExists ? nil : "Verify the game files in Steam or select the correct executable."
            ))
            
            // Kernel Anti-Cheat warning if detected
            if g.compatibilityStatus == .unsupported {
                items.append(DiagnosticCheckItem(
                    category: "Game Security",
                    title: "Anti-Cheat Compatibility",
                    passed: false,
                    severity: .error,
                    message: g.compatibilityReason ?? "Kernel-level anti-cheat detected.",
                    details: "Windows kernel drivers (.sys) cannot execute inside user-mode macOS Wine translation.",
                    remediationSuggestion: "Check if the game developer provides a native Mac version or launch in single-player offline mode if supported."
                ))
            }
            
            // Game Prefix Check
            let prefix = prefixManager.getPrefix(forGameId: g.prefixId)
            let prefixReady = prefix != nil
            items.append(DiagnosticCheckItem(
                category: "Prefix",
                title: "Isolated Wine Prefix",
                passed: prefixReady,
                severity: prefixReady ? .success : .warning,
                message: prefixReady ? "Prefix initialized at: \(prefix?.path ?? "")" : "Prefix will be automatically initialized at launch.",
                details: "Wine architecture: \(prefix?.wineArchitecture ?? "win64")",
                remediationSuggestion: prefixReady ? nil : "Click 'Repair Prefix' or launch the game to automatically generate the environment."
            ))
        }
        
        let allPassed = !items.contains(where: { $0.severity == .error })
        let summary = allPassed ? "Everything required to launch this game appears ready." : "One or more critical dependencies need attention before launching."
        
        return DiagnosticReport(
            hardwareSummary: hardware,
            items: items,
            overallPassed: allPassed,
            summaryMessage: summary
        )
    }
}
