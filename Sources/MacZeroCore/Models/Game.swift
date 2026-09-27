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
    case externalDrive = "External Drive"
    case internalStorage = "Internal Storage"
    case steam = "Steam"
    case epic = "Epic Games"
    case gog = "GOG"
    case custom = "Custom"
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

public enum LaunchMode: String, Codable, CaseIterable, Sendable {
    case directExecutable = "Direct Executable"
    case steam = "Steam Client"
    case launcher = "Game Launcher"
}

public enum PrefixLocationType: String, Codable, CaseIterable, Sendable {
    case internalStorage = "Mac Internal Storage"
    case externalDrive = "Same External Drive"
    case custom = "Custom Location"
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
    
    // External Game Drive & Steam Library Properties
    public var driveIdentifier: String?
    public var volumeName: String?
    public var volumeUUID: String?
    public var relativePath: String?
    public var steamLibraryPath: String?
    public var isExternal: Bool
    public var isDriveConnected: Bool
    public var securityBookmarkData: Data?
    public var launchMode: LaunchMode
    public var prefixLocationType: PrefixLocationType
    public var externalPrefixPath: String?
    
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
        updatedAt: Date = Date(),
        driveIdentifier: String? = nil,
        volumeName: String? = nil,
        volumeUUID: String? = nil,
        relativePath: String? = nil,
        steamLibraryPath: String? = nil,
        isExternal: Bool = false,
        isDriveConnected: Bool = true,
        securityBookmarkData: Data? = nil,
        launchMode: LaunchMode = .directExecutable,
        prefixLocationType: PrefixLocationType = .internalStorage,
        externalPrefixPath: String? = nil
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
        self.driveIdentifier = driveIdentifier
        self.volumeName = volumeName
        self.volumeUUID = volumeUUID
        self.relativePath = relativePath
        self.steamLibraryPath = steamLibraryPath
        self.isExternal = isExternal
        self.isDriveConnected = isDriveConnected
        self.securityBookmarkData = securityBookmarkData
        self.launchMode = launchMode
        self.prefixLocationType = prefixLocationType
        self.externalPrefixPath = externalPrefixPath
    }
    
    // Convenience Accessors matching URL-based and section 48 specifications
    public var name: String {
        get { title }
        set { title = newValue }
    }
    
    public var gameURL: URL {
        return URL(fileURLWithPath: workingDirectory ?? (executablePath as NSString).deletingLastPathComponent)
    }
    
    public var executableURL: URL? {
        return URL(fileURLWithPath: executablePath)
    }
    
    public var volumeIdentifier: String? {
        return driveIdentifier ?? volumeUUID
    }
    
    public var compatibilityProfile: String? {
        return profileId
    }
    
    public var runtimeVersion: String? {
        return runtimeId
    }
    
    public var playTime: TimeInterval {
        get { Double(playTimeSeconds) }
        set { playTimeSeconds = Int(newValue) }
    }
    
    public var isReady: Bool {
        return !isExternal || isDriveConnected
    }
}

public struct GameVerificationItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let passed: Bool
    public let detail: String
    
    public init(name: String, passed: Bool, detail: String) {
        self.id = name
        self.name = name
        self.passed = passed
        self.detail = detail
    }
}

public struct GameVerificationResult: Codable, Equatable, Hashable, Sendable {
    public let gameId: String
    public let gameTitle: String
    public let overallPassed: Bool
    public let items: [GameVerificationItem]
    public let verifiedAt: Date
    
    public init(gameId: String, gameTitle: String, overallPassed: Bool, items: [GameVerificationItem], verifiedAt: Date = Date()) {
        self.gameId = gameId
        self.gameTitle = gameTitle
        self.overallPassed = overallPassed
        self.items = items
        self.verifiedAt = verifiedAt
    }
}

