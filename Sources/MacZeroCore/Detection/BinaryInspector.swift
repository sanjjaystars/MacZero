import Foundation

public struct BinaryAnalysisResult: Sendable {
    public let architecture: BinaryArchitecture
    public let detectedApis: [GraphicsAPI]
    public let primaryApi: GraphicsAPI
    public let antiCheatDetected: String?
    public let drmDetected: String?
    public let importedDlls: [String]
    public let isKernelDriverDependent: Bool
    public let recommendedStatus: CompatibilityStatus
    public let compatibilityReason: String
}

public final class BinaryInspector: Sendable {
    public static let shared = BinaryInspector()
    
    public init() {}
    
    public func inspect(executablePath: String) -> BinaryAnalysisResult {
        guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: executablePath), options: .alwaysMapped) else {
            return BinaryAnalysisResult(
                architecture: .unknown,
                detectedApis: [.unknown],
                primaryApi: .unknown,
                antiCheatDetected: nil,
                drmDetected: nil,
                importedDlls: [],
                isKernelDriverDependent: false,
                recommendedStatus: .unknown,
                compatibilityReason: "Could not read binary file."
            )
        }
        
        let arch = inspectArchitecture(data: fileData)
        let dllsAndStrings = extractInterestingStrings(from: fileData)
        
        var apis: [GraphicsAPI] = []
        if dllsAndStrings.contains(where: { $0.lowercased().contains("d3d12.dll") || $0.lowercased().contains("dxgi.dll") && $0.lowercased().contains("d3d12") }) {
            apis.append(.dx12)
        }
        if dllsAndStrings.contains(where: { $0.lowercased().contains("d3d11.dll") }) {
            apis.append(.dx11)
        }
        if dllsAndStrings.contains(where: { $0.lowercased().contains("d3d10.dll") || $0.lowercased().contains("d3d10_1.dll") }) {
            apis.append(.dx10)
        }
        if dllsAndStrings.contains(where: { $0.lowercased().contains("d3d9.dll") }) {
            apis.append(.dx9)
        }
        if dllsAndStrings.contains(where: { $0.lowercased().contains("vulkan-1.dll") || $0.lowercased().contains("vkcreateinstance") }) {
            apis.append(.vulkan)
        }
        
        let primaryApi = apis.first ?? .unknown
        
        // Anti-cheat detection (Kernel-level vs user-mode)
        var antiCheat: String? = nil
        var isKernelDependent = false
        
        let lowerStrings = dllsAndStrings.map { $0.lowercased() }
        if lowerStrings.contains(where: { $0.contains("easyanticheat") || $0.contains("easyanticheat_x64.dll") }) {
            antiCheat = "Easy Anti-Cheat (EAC)"
            isKernelDependent = true
        } else if lowerStrings.contains(where: { $0.contains("battleye") || $0.contains("beservice") }) {
            antiCheat = "BattlEye"
            isKernelDependent = true
        } else if lowerStrings.contains(where: { $0.contains("vanguard") || $0.contains("vgk.sys") }) {
            antiCheat = "Riot Vanguard"
            isKernelDependent = true
        } else if lowerStrings.contains(where: { $0.contains("ricochet") }) {
            antiCheat = "Ricochet Kernel Anti-Cheat"
            isKernelDependent = true
        }
        
        // DRM detection
        var drm: String? = nil
        if lowerStrings.contains(where: { $0.contains("denuvo") }) {
            drm = "Denuvo Anti-Tamper"
        }
        
        // Determine honest compatibility
        let status: CompatibilityStatus
        let reason: String
        
        if isKernelDependent {
            status = .unsupported
            reason = "Game utilizes \(antiCheat ?? "kernel-level anti-cheat") which requires Windows NT kernel ring-0 drivers unsupported on macOS."
        } else if drm != nil {
            status = .experimental
            reason = "Game contains \(drm!). May execute depending on Wine compatibility and online licensing checks."
        } else if primaryApi == .dx12 {
            status = .compatible
            reason = "DirectX 12 translation ready via VKD3D-Proton → MoltenVK → Metal on Apple Silicon."
        } else if primaryApi == .dx11 || primaryApi == .dx9 {
            status = .compatible
            reason = "DirectX \(primaryApi.shortName) translation supported via DXVK → MoltenVK → Metal."
        } else if primaryApi == .vulkan {
            status = .compatible
            reason = "Vulkan game natively mapped to Metal via MoltenVK."
        } else {
            status = .experimental
            reason = "Executable detected with standard Windows PE format. Using default compatibility profile."
        }
        
        return BinaryAnalysisResult(
            architecture: arch,
            detectedApis: apis.isEmpty ? [.unknown] : apis,
            primaryApi: primaryApi,
            antiCheatDetected: antiCheat,
            drmDetected: drm,
            importedDlls: dllsAndStrings.filter { $0.hasSuffix(".dll") },
            isKernelDriverDependent: isKernelDependent,
            recommendedStatus: status,
            compatibilityReason: reason
        )
    }
    
    private func inspectArchitecture(data: Data) -> BinaryArchitecture {
        // Look for DOS header 'MZ' (0x5A4D)
        guard data.count >= 0x40 else { return .unknown }
        let e_magic = data.withUnsafeBytes { $0.load(as: UInt16.self) }
        guard e_magic == 0x5A4D else { return .unknown }
        
        // Offset to PE Header at 0x3C
        let e_lfanew = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 0x3C, as: UInt32.self) })
        guard data.count >= e_lfanew + 24 else { return .unknown }
        
        // Verify PE signature 'PE\0\0' (0x00004550)
        let pe_sig = data.withUnsafeBytes { $0.load(fromByteOffset: e_lfanew, as: UInt32.self) }
        guard pe_sig == 0x00004550 else { return .unknown }
        
        // Machine type is at e_lfanew + 4 (UInt16)
        let machine = data.withUnsafeBytes { $0.load(fromByteOffset: e_lfanew + 4, as: UInt16.self) }
        switch machine {
        case 0x8664:
            return .x86_64 // AMD64 / x86_64
        case 0xAA64:
            return .arm64  // ARM64 Windows
        case 0x014C:
            return .x86_32 // Intel 386 / 32-bit
        default:
            return .unknown
        }
    }
    
    private func extractInterestingStrings(from data: Data) -> [String] {
        var results = Set<String>()
        let targetKeywords = [
            "d3d12.dll", "d3d11.dll", "d3d10.dll", "d3d10_1.dll", "d3d9.dll", "dxgi.dll",
            "vulkan-1.dll", "vkcreateinstance", "easyanticheat", "battleye", "vanguard", "denuvo",
            "xinput1_3.dll", "xinput1_4.dll", "xinput9_1_0.dll", "steam_api64.dll", "steam_api.dll",
            "galaxy64.dll", "eossdk-win64-shipping.dll"
        ]
        
        let scanLength = min(data.count, 2 * 1024 * 1024)
        let prefixData = data.subdata(in: 0..<scanLength)
        let prefixString = String(decoding: prefixData, as: UTF8.self).lowercased()
        
        for kw in targetKeywords {
            if prefixString.contains(kw) {
                results.insert(kw)
            }
        }
        
        // Also scan trailing data for import tables
        if data.count > 4 * 1024 * 1024 {
            let suffixStart = data.count - (2 * 1024 * 1024)
            let suffixData = data.subdata(in: suffixStart..<data.count)
            let suffixString = String(decoding: suffixData, as: UTF8.self).lowercased()
            for kw in targetKeywords {
                if suffixString.contains(kw) {
                    results.insert(kw)
                }
            }
        }
        
        return Array(results)
    }
}
