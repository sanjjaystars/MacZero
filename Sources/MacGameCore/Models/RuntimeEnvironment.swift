import Foundation

public enum RuntimeType: String, Codable, CaseIterable, Sendable {
    case wine = "Wine"
    case gptk = "Game Porting Toolkit (GPTK)"
    case vkd3d = "VKD3D-Proton"
    case dxvk = "DXVK"
    case moltenvk = "MoltenVK"
}

public enum RuntimeArchitecture: String, Codable, Sendable {
    case arm64 = "ARM64 (Native Apple Silicon)"
    case x86_64 = "x86_64 (Rosetta 2)"
    case universal = "Universal (ARM64 + x86_64)"
}

public struct RuntimeComponent: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var type: RuntimeType
    public var version: String
    public var architecture: RuntimeArchitecture
    public var installPath: String
    public var binaryPath: String?
    public var libraryPath: String?
    public var isInstalled: Bool
    public var isValid: Bool
    public var isDefault: Bool
    public var releaseDate: Date?
    public var releaseNotes: String?
    
    public init(
        id: String,
        name: String,
        type: RuntimeType,
        version: String,
        architecture: RuntimeArchitecture = .arm64,
        installPath: String,
        binaryPath: String? = nil,
        libraryPath: String? = nil,
        isInstalled: Bool = false,
        isValid: Bool = false,
        isDefault: Bool = false,
        releaseDate: Date? = nil,
        releaseNotes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.version = version
        self.architecture = architecture
        self.installPath = installPath
        self.binaryPath = binaryPath
        self.libraryPath = libraryPath
        self.isInstalled = isInstalled
        self.isValid = isValid
        self.isDefault = isDefault
        self.releaseDate = releaseDate
        self.releaseNotes = releaseNotes
    }
}
