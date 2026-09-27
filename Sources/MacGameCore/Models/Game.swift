import Foundation

public enum GraphicsAPI: String, Codable, CaseIterable, Sendable {
    case dx12 = "DirectX 12"
    case dx11 = "DirectX 11"
    case dx10 = "DirectX 10"
    case dx9 = "DirectX 9"
    case vulkan = "Vulkan"
    case unknown = "Unknown"
    
    public var shortName: String {
        switch self {
        case .dx12: return "DX12"
        case .dx11: return "DX11"
        case .dx10: return "DX10"
        case .dx9: return "DX9"
        case .vulkan: return "VK"
        case .unknown: return "Unknown"
        }
    }
    
    public var defaultTranslationLayer: String {
        switch self {
        case .dx12: return "VKD3D-Proton"
        case .dx11, .dx10, .dx9: return "DXVK"
        case .vulkan: return "MoltenVK (Direct)"
        case .unknown: return "Automatic"
        }
    }
}

public enum BinaryArchitecture: String, Codable, CaseIterable, Sendable {
    case x86_64 = "x86_64 (64-bit)"
    case arm64 = "ARM64"
    case x86_32 = "x86 (32-bit)"
    case unknown = "Unknown"
}

public enum GameSource: String, Codable, CaseIterable, Sendable {
    case steam = "Steam"
    case epic = "Epic Games"
    case gog = "GOG"
    case customExe = "Executable (.exe)"
    case folder = "Game Folder"
    case iso = "Disk Image (.iso)"
}

public enum CompatibilityStatus: String, Codable, CaseIterable, Sendable {
    case compatible = "Compatible"
    case experimental = "Experimental"
    case unsupported = "Unsupported"
    case unknown = "Unknown"
    
    public var icon: String {
        switch self {
        case .compatible: return "🟢"
        case .experimental: return "🟡"
        case .unsupported: return "🔴"
        case .unknown: return "⚪"
        }
    }
    
    public var badgeText: String {
        return "\(icon) \(rawValue)"
    }
}

public enum GameLaunchMode: String, Codable, Sendable {
    case standard = "Standard"
    case safeMode = "Safe Mode"
    case diagnostics = "Diagnostics Only"
}

public struct Game: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var executablePath: String
    public var workingDirectory: String?
    public var source: GameSource
    public var sourceAppId: String? // e.g. Steam App ID
    public var graphicsApi: GraphicsAPI
    public var architecture: BinaryArchitecture
    public var compatibilityStatus: CompatibilityStatus
    public var compatibilityReason: String?
    public var prefixId: String
    public var runtimeId: String
    public var profileId: String
    public var launchArguments: [String]
    public var environmentVariables: [String: String]
    public var lastPlayed: Date?
    public var playTimeSeconds: Int
    public var isFavorite: Bool
    public var bannerImagePath: String?
    public var iconPath: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        executablePath: String,
        workingDirectory: String? = nil,
        source: GameSource = .customExe,
        sourceAppId: String? = nil,
        graphicsApi: GraphicsAPI = .dx12,
        architecture: BinaryArchitecture = .x86_64,
        compatibilityStatus: CompatibilityStatus = .unknown,
        compatibilityReason: String? = nil,
        prefixId: String? = nil,
        runtimeId: String = "wine-system",
        profileId: String = "default",
        launchArguments: [String] = [],
        environmentVariables: [String: String] = [:],
        lastPlayed: Date? = nil,
        playTimeSeconds: Int = 0,
        isFavorite: Bool = false,
        bannerImagePath: String? = nil,
        iconPath: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory ?? (executablePath as NSString).deletingLastPathComponent
        self.source = source
        self.sourceAppId = sourceAppId
        self.graphicsApi = graphicsApi
        self.architecture = architecture
        self.compatibilityStatus = compatibilityStatus
        self.compatibilityReason = compatibilityReason
        self.prefixId = prefixId ?? id
        self.runtimeId = runtimeId
        self.profileId = profileId
        self.launchArguments = launchArguments
        self.environmentVariables = environmentVariables
        self.lastPlayed = lastPlayed
        self.playTimeSeconds = playTimeSeconds
        self.isFavorite = isFavorite
        self.bannerImagePath = bannerImagePath
        self.iconPath = iconPath
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
