import Foundation

public protocol RuntimeManagerProtocol: Sendable {
    func listRuntimes() -> [RuntimeComponent]
    func defaultWineRuntime() -> RuntimeComponent?
    func defaultDx12Runtime() -> RuntimeComponent?
    func defaultVulkanRuntime() -> RuntimeComponent?
    func verifyRuntime(id: String) -> (isValid: Bool, message: String)
    func installOrUpdateLocalComponent(type: RuntimeType, version: String, customPath: String) throws -> RuntimeComponent
    func removeComponent(id: String) throws
}

public final class RuntimeManager: RuntimeManagerProtocol, Sendable {
    public static let shared = RuntimeManager()
    
    private let pathProvider: PathProvider
    
    public init(pathProvider: PathProvider = .shared) {
        self.pathProvider = pathProvider
    }
    
    public func listRuntimes() -> [RuntimeComponent] {
        var components: [RuntimeComponent] = []
        
        // 1. Check MoltenVK (Homebrew and custom)
        let brewMolten = "/opt/homebrew/opt/molten-vk/lib/libMoltenVK.dylib"
        let isBrewMoltenInstalled = FileManager.default.fileExists(atPath: brewMolten)
        components.append(RuntimeComponent(
            id: "moltenvk-system",
            name: "MoltenVK (System / Homebrew)",
            type: .moltenvk,
            version: "1.2.9+",
            architecture: .arm64,
            installPath: "/opt/homebrew/opt/molten-vk",
            binaryPath: nil,
            libraryPath: brewMolten,
            isInstalled: isBrewMoltenInstalled,
            isValid: isBrewMoltenInstalled,
            isDefault: true,
            releaseNotes: "Native Vulkan to Metal translation layer for Apple Silicon."
        ))
        
        // 2. Check VKD3D-Proton
        let vkd3dCustom = pathProvider.runtimesDirectory.appendingPathComponent("vkd3d/x64/d3d12.dll").path
        let isVkd3dInstalled = FileManager.default.fileExists(atPath: vkd3dCustom)
        components.append(RuntimeComponent(
            id: "vkd3d-proton-2.12",
            name: "VKD3D-Proton (DirectX 12 Translation)",
            type: .vkd3d,
            version: "2.12",
            architecture: .universal,
            installPath: pathProvider.runtimesDirectory.appendingPathComponent("vkd3d").path,
            binaryPath: nil,
            libraryPath: vkd3dCustom,
            isInstalled: isVkd3dInstalled,
            isValid: isVkd3dInstalled,
            isDefault: true,
            releaseNotes: "DirectX 12 translation engine targetting Vulkan."
        ))
        
        // 3. Check DXVK
        let dxvkCustom = pathProvider.runtimesDirectory.appendingPathComponent("dxvk/x64/d3d11.dll").path
        let isDxvkInstalled = FileManager.default.fileExists(atPath: dxvkCustom)
        components.append(RuntimeComponent(
            id: "dxvk-2.3",
            name: "DXVK (DirectX 9/10/11 Translation)",
            type: .dxvk,
            version: "2.3.1",
            architecture: .universal,
            installPath: pathProvider.runtimesDirectory.appendingPathComponent("dxvk").path,
            binaryPath: nil,
            libraryPath: dxvkCustom,
            isInstalled: isDxvkInstalled,
            isValid: isDxvkInstalled,
            isDefault: true,
            releaseNotes: "DirectX 9/10/11 translation layer to Vulkan."
        ))
        
        // 4. Check Wine runners (Search Homebrew, /usr/local, Application Support, Whisky, CrossOver)
        let wineSearchPaths = [
            "/opt/homebrew/bin/wine64",
            "/opt/homebrew/bin/wine",
            "/usr/local/bin/wine64",
            "/usr/local/bin/wine",
            "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine64",
            "/Applications/Whisky.app/Contents/Resources/wine/bin/wine64",
            pathProvider.runtimesDirectory.appendingPathComponent("wine/bin/wine64").path
        ]
        
        var foundWine = false
        for winePath in wineSearchPaths {
            if FileManager.default.fileExists(atPath: winePath) {
                let isArm64 = !winePath.contains("CrossOver") // CrossOver is typically x86_64
                components.append(RuntimeComponent(
                    id: "wine-\((winePath as NSString).lastPathComponent)-\(UUID().uuidString.prefix(4))",
                    name: "Wine Runner (\((winePath as NSString).deletingLastPathComponent))",
                    type: .wine,
                    version: "9.0+ Staging",
                    architecture: isArm64 ? .arm64 : .x86_64,
                    installPath: (winePath as NSString).deletingLastPathComponent,
                    binaryPath: winePath,
                    libraryPath: nil,
                    isInstalled: true,
                    isValid: true,
                    isDefault: !foundWine,
                    releaseNotes: "Discovered Wine binary on local filesystem."
                ))
                foundWine = true
            }
        }
        
        // If no external wine is found yet, provide the configured runtime stub entry
        if !foundWine {
            let localWineDir = pathProvider.runtimesDirectory.appendingPathComponent("wine")
            components.append(RuntimeComponent(
                id: "wine-local",
                name: "Wine 9.0 Apple Silicon Runner",
                type: .wine,
                version: "9.0-staging",
                architecture: .arm64,
                installPath: localWineDir.path,
                binaryPath: localWineDir.appendingPathComponent("bin/wine64").path,
                libraryPath: localWineDir.appendingPathComponent("lib").path,
                isInstalled: false,
                isValid: false,
                isDefault: true,
                releaseNotes: "Primary Wine runner for Windows API emulation on Apple Silicon."
            ))
        }
        
        // 5. Apple Game Porting Toolkit (GPTK)
        let gptkLib = "/usr/local/include/libd3dshared.dylib"
        let isGptkInstalled = FileManager.default.fileExists(atPath: gptkLib)
        components.append(RuntimeComponent(
            id: "gptk-2.0",
            name: "Apple Game Porting Toolkit (GPTK 2)",
            type: .gptk,
            version: "2.0-beta",
            architecture: .arm64,
            installPath: "/usr/local/include",
            binaryPath: nil,
            libraryPath: isGptkInstalled ? gptkLib : nil,
            isInstalled: isGptkInstalled,
            isValid: isGptkInstalled,
            isDefault: false,
            releaseNotes: "Apple proprietary D3D-to-Metal direct translation engine."
        ))
        
        return components
    }
    
    public func defaultWineRuntime() -> RuntimeComponent? {
        let all = listRuntimes().filter { $0.type == .wine }
        return all.first(where: { $0.isInstalled && $0.isValid }) ?? all.first
    }
    
    public func defaultDx12Runtime() -> RuntimeComponent? {
        let all = listRuntimes().filter { $0.type == .vkd3d }
        return all.first(where: { $0.isInstalled }) ?? all.first
    }
    
    public func defaultVulkanRuntime() -> RuntimeComponent? {
        let all = listRuntimes().filter { $0.type == .moltenvk }
        return all.first(where: { $0.isInstalled }) ?? all.first
    }
    
    public func verifyRuntime(id: String) -> (isValid: Bool, message: String) {
        guard let component = listRuntimes().first(where: { $0.id == id }) else {
            return (false, "Runtime component not found.")
        }
        
        if let bin = component.binaryPath {
            if !FileManager.default.fileExists(atPath: bin) {
                return (false, "Binary not present at path: \(bin)")
            }
            if !FileManager.default.isExecutableFile(atPath: bin) {
                return (false, "File at \(bin) is not executable.")
            }
            return (true, "Binary verified executable at \(bin).")
        }
        
        if let lib = component.libraryPath {
            if !FileManager.default.fileExists(atPath: lib) {
                return (false, "Dynamic library not present at: \(lib)")
            }
            return (true, "Library verified at \(lib).")
        }
        
        return (false, "No executable binary or dynamic library configured for \(component.name).")
    }
    
    public func installOrUpdateLocalComponent(type: RuntimeType, version: String, customPath: String) throws -> RuntimeComponent {
        try pathProvider.ensureDirectoriesExist()
        let subfolder: String
        switch type {
        case .wine: subfolder = "wine"
        case .gptk: subfolder = "gptk"
        case .vkd3d: subfolder = "vkd3d"
        case .dxvk: subfolder = "dxvk"
        case .moltenvk: subfolder = "moltenvk"
        }
        
        let targetDir = pathProvider.runtimesDirectory.appendingPathComponent(subfolder)
        let sourceURL = URL(fileURLWithPath: customPath)
        
        if FileManager.default.fileExists(atPath: targetDir.path) {
            try FileManager.default.removeItem(at: targetDir)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetDir)
        
        return RuntimeComponent(
            id: "\(subfolder)-custom",
            name: "\(type.rawValue) (\(version))",
            type: type,
            version: version,
            architecture: .arm64,
            installPath: targetDir.path,
            binaryPath: targetDir.appendingPathComponent("bin/\(subfolder)").path,
            isInstalled: true,
            isValid: true,
            isDefault: true
        )
    }
    
    public func removeComponent(id: String) throws {
        guard let component = listRuntimes().first(where: { $0.id == id }) else { return }
        let url = URL(fileURLWithPath: component.installPath)
        // Only allow deleting within MacZero runtimes directory for security
        if url.path.hasPrefix(pathProvider.runtimesDirectory.path) {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }
}
