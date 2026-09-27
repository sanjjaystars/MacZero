import Foundation

public enum PrefixStatus: String, Codable, Sendable {
    case ready = "Ready"
    case uninitialized = "Uninitialized"
    case repairing = "Repairing"
    case damaged = "Damaged"
}

public struct GamePrefix: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var path: String
    public var wineArchitecture: String // "win64" or "win32"
    public var wineVersion: String?
    public var status: PrefixStatus
    public var dllOverrides: [String: String] // e.g. "d3d12": "native,builtin"
    public var registryEntries: [String: String]
    public var installedDependencies: [String] // e.g. "vcrun2022", "d3dcompiler_47"
    public var createdAt: Date
    public var lastModified: Date
    public var isLocked: Bool
    
    public init(
        id: String,
        name: String,
        path: String,
        wineArchitecture: String = "win64",
        wineVersion: String? = nil,
        status: PrefixStatus = .uninitialized,
        dllOverrides: [String: String] = [:],
        registryEntries: [String: String] = [:],
        installedDependencies: [String] = [],
        createdAt: Date = Date(),
        lastModified: Date = Date(),
        isLocked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.wineArchitecture = wineArchitecture
        self.wineVersion = wineVersion
        self.status = status
        self.dllOverrides = dllOverrides
        self.registryEntries = registryEntries
        self.installedDependencies = installedDependencies
        self.createdAt = createdAt
        self.lastModified = lastModified
        self.isLocked = isLocked
    }
}
