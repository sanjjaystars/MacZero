import Foundation

public struct DX12TuningOptions: Sendable {
    public var enableShaderCache: Bool
    public var enableRayTracing: Bool
    public var enableAsyncPso: Bool
    public var singleQueueMode: Bool
    public var featureLevel: String // "12_1", "12_0", "11_1"
    public var metalFxUpscaling: Bool
    public var esyncEnabled: Bool
    public var fsyncEnabled: Bool
    
    public init(
        enableShaderCache: Bool = true,
        enableRayTracing: Bool = false,
        enableAsyncPso: Bool = true,
        singleQueueMode: Bool = true,
        featureLevel: String = "12_1",
        metalFxUpscaling: Bool = false,
        esyncEnabled: Bool = true,
        fsyncEnabled: Bool = true
    ) {
        self.enableShaderCache = enableShaderCache
        self.enableRayTracing = enableRayTracing
        self.enableAsyncPso = enableAsyncPso
        self.singleQueueMode = singleQueueMode
        self.featureLevel = featureLevel
        self.metalFxUpscaling = metalFxUpscaling
        self.esyncEnabled = esyncEnabled
        self.fsyncEnabled = fsyncEnabled
    }
}

public final class DX12Optimizer: Sendable {
    public static let shared = DX12Optimizer()
    
    public init() {}
    
    public func generateEnvironment(options: DX12TuningOptions, hardware: HardwareSpecs) -> [String: String] {
        var env: [String: String] = [:]
        
        // 1. VKD3D-Proton options
        var vkd3dFlags: [String] = []
        if options.enableShaderCache {
            vkd3dFlags.append("shader_cache")
        }
        if options.singleQueueMode {
            vkd3dFlags.append("single_queue")
        }
        
        // Hardware Ray Tracing check on Apple Silicon (M3/M4/M5 support hardware RT)
        let supportsHardwareRT = hardware.chipGeneration.contains("M3") || hardware.chipGeneration.contains("M4") || hardware.chipGeneration.contains("M5")
        if options.enableRayTracing && supportsHardwareRT {
            vkd3dFlags.append("dxr11")
        }
        
        env["VKD3D_CONFIG"] = vkd3dFlags.joined(separator: ",")
        env["VKD3D_FEATURE_LEVEL"] = options.featureLevel
        
        // 2. MoltenVK Vulkan translation settings
        // Enable fast Apple Silicon unified memory caching
        env["MVK_CONFIG_RES_PATH"] = "/opt/homebrew/share/vulkan/icd.d"
        env["MVK_CONFIG_FAST_MATH_ENABLED"] = "1"
        env["MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS"] = options.singleQueueMode ? "1" : "0"
        
        // 3. Wine synchronization options
        if options.esyncEnabled {
            env["WINEESYNC"] = "1"
        }
        if options.fsyncEnabled {
            env["WINEFSYNC"] = "1"
        }
        env["WINE_LARGE_ADDRESS_AWARE"] = "1"
        
        // 4. Vulkan ICD discovery for MoltenVK
        let homebrewIcd = "/opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json"
        if FileManager.default.fileExists(atPath: homebrewIcd) {
            env["VK_ICD_FILENAMES"] = homebrewIcd
        }
        
        return env
    }
    
    public func recommendedDllOverrides() -> [String: String] {
        return [
            "d3d12": "native,builtin",
            "dxgi": "native,builtin",
            "d3d12core": "native,builtin"
        ]
    }
}
