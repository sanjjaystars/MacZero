import Foundation

public protocol ProfileEngineProtocol: Sendable {
    func loadAllProfiles() -> [CompatibilityProfile]
    func profile(withId id: String) -> CompatibilityProfile?
    func matchProfile(forTitle title: String, executablePath: String, api: GraphicsAPI) -> CompatibilityProfile
    func saveProfile(_ profile: CompatibilityProfile) throws
}

public final class ProfileEngine: ProfileEngineProtocol, Sendable {
    public static let shared = ProfileEngine()
    
    private let pathProvider: PathProvider
    
    public init(pathProvider: PathProvider = .shared) {
        self.pathProvider = pathProvider
    }
    
    public func loadAllProfiles() -> [CompatibilityProfile] {
        var profilesMap: [String: CompatibilityProfile] = [:]
        
        // 1. Built-in fallback profiles
        let defaults = builtInProfiles()
        for p in defaults {
            profilesMap[p.id] = p
        }
        
        // 2. Check Application Support custom profiles
        let customDir = pathProvider.profilesDirectory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: customDir.path) {
            for file in files where file.hasSuffix(".json") {
                let fileURL = customDir.appendingPathComponent(file)
                if let data = try? Data(contentsOf: fileURL),
                   let customProfile = try? JSONDecoder().decode(CompatibilityProfile.self, from: data) {
                    profilesMap[customProfile.id] = customProfile
                }
            }
        }
        
        return Array(profilesMap.values).sorted { $0.gameTitle < $1.gameTitle }
    }
    
    public func profile(withId id: String) -> CompatibilityProfile? {
        return loadAllProfiles().first { $0.id == id }
    }
    
    public func matchProfile(forTitle title: String, executablePath: String, api: GraphicsAPI) -> CompatibilityProfile {
        let all = loadAllProfiles()
        let lowerTitle = title.lowercased()
        let lowerExe = (executablePath as NSString).lastPathComponent.lowercased()
        
        // Check exact or partial title match
        if lowerTitle.contains("mortal kombat") || lowerExe.contains("mk12") || lowerExe.contains("mortalkombat") {
            if let p = all.first(where: { $0.id == "mortal-kombat-1" }) {
                return p
            }
        }
        
        if lowerTitle.contains("cyberpunk") || lowerExe.contains("cyberpunk2077") {
            if let p = all.first(where: { $0.id == "cyberpunk-2077" }) {
                return p
            }
        }
        
        if lowerTitle.contains("elden ring") || lowerExe.contains("eldenring") {
            if let p = all.first(where: { $0.id == "elden-ring" }) {
                return p
            }
        }
        
        // Fallback to default or matching API profile
        return profile(withId: "default") ?? builtInDefaultProfile()
    }
    
    public func saveProfile(_ profile: CompatibilityProfile) throws {
        try pathProvider.ensureDirectoriesExist()
        let targetFile = pathProvider.profilesDirectory.appendingPathComponent("\(profile.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: targetFile)
    }
    
    private func builtInProfiles() -> [CompatibilityProfile] {
        return [
            CompatibilityProfile(
                id: "mortal-kombat-1",
                gameTitle: "Mortal Kombat 1",
                graphicsApi: .dx12,
                runtimeRecommendation: "Wine 9.0+ / GPTK 2",
                vkd3dConfig: ["dxr11", "shader_cache", "single_queue"],
                environment: [
                    "VKD3D_CONFIG": "dxr11,shader_cache,single_queue",
                    "VKD3D_FEATURE_LEVEL": "12_1",
                    "MVK_CONFIG_RES_PATH": "/opt/homebrew/share/vulkan/icd.d",
                    "WINEESYNC": "1",
                    "WINEFSYNC": "1",
                    "WINE_LARGE_ADDRESS_AWARE": "1"
                ],
                dllOverrides: ["d3d12": "native,builtin", "dxgi": "native,builtin"],
                launchArguments: ["-dx12", "-novid"],
                dependencies: ["vcrun2022", "d3dcompiler_47"],
                knownIssues: [
                    "Online ranked matchmaking requiring kernel driver anti-cheat will fail; offline story and local modes work reliably.",
                    "First-time shader compilation may show minor initial frame drops."
                ],
                recommendedSettings: [
                    "Shader Cache": "Enabled (Apple Silicon Unified Memory)",
                    "Upscaling": "AMD FSR 2.2 / MetalFX Quality",
                    "DirectX Version": "DX12 Ultimate (Feature Level 12_1)",
                    "Frame Rate Target": "60 FPS V-Sync Locked"
                ],
                version: 1,
                author: "MacGame Compatibility Team",
                notes: "Verified on Apple Silicon M-series via VKD3D-Proton 2.12+ mapped through MoltenVK onto Metal 3."
            ),
            CompatibilityProfile(
                id: "cyberpunk-2077",
                gameTitle: "Cyberpunk 2077",
                graphicsApi: .dx12,
                runtimeRecommendation: "Wine 9.0+ / GPTK 2",
                vkd3dConfig: ["dxr", "shader_cache", "single_queue"],
                environment: [
                    "VKD3D_CONFIG": "dxr,shader_cache,single_queue",
                    "VKD3D_FEATURE_LEVEL": "12_1",
                    "WINEESYNC": "1",
                    "WINEFSYNC": "1"
                ],
                dllOverrides: ["d3d12": "native,builtin", "dxgi": "native,builtin"],
                launchArguments: ["-skipStartScreen"],
                dependencies: ["vcrun2022", "d3dcompiler_47"],
                knownIssues: ["High ray-tracing settings require M3 Max/Ultra or M4 Max hardware."],
                recommendedSettings: ["FSR 2.1": "Quality or Balanced", "Crowd Density": "Medium"],
                version: 1,
                author: "MacGame Compatibility Team"
            ),
            CompatibilityProfile(
                id: "elden-ring",
                gameTitle: "Elden Ring",
                graphicsApi: .dx12,
                runtimeRecommendation: "Wine 9.0+ / VKD3D-Proton",
                vkd3dConfig: ["shader_cache"],
                environment: [
                    "VKD3D_CONFIG": "shader_cache",
                    "WINEESYNC": "1",
                    "WINEFSYNC": "1"
                ],
                dllOverrides: ["d3d12": "native,builtin", "dxgi": "native,builtin"],
                launchArguments: [],
                dependencies: ["vcrun2022"],
                knownIssues: ["EAC requires offline mode switch for single-player play."],
                recommendedSettings: ["Framerate": "60 FPS", "Quality Preset": "High (M2 Pro/M3/M4)"],
                version: 1,
                author: "MacGame Compatibility Team"
            ),
            builtInDefaultProfile()
        ]
    }
    
    private func builtInDefaultProfile() -> CompatibilityProfile {
        return CompatibilityProfile(
            id: "default",
            gameTitle: "Default Compatibility Profile",
            graphicsApi: .dx12,
            runtimeRecommendation: "Wine 9.0+ / GPTK",
            vkd3dConfig: ["shader_cache"],
            environment: [
                "VKD3D_CONFIG": "shader_cache",
                "WINEESYNC": "1",
                "WINEFSYNC": "1"
            ],
            dllOverrides: ["d3d12": "native,builtin", "dxgi": "native,builtin", "d3d11": "native,builtin"],
            launchArguments: [],
            dependencies: ["vcrun2022"],
            knownIssues: ["Kernel-level anti-cheat drivers cannot run in Wine translation."],
            recommendedSettings: ["Shader Cache": "Enabled", "Resolution": "1920x1080 or Native Display"],
            version: 1,
            author: "MacGame System",
            notes: "Safe default profile for unrecognized or newly installed games."
        )
    }
}
