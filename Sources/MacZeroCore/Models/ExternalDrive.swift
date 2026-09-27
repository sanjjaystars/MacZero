import Foundation

public struct DriveBenchmarkResult: Codable, Equatable, Hashable, Sendable {
    public let readSpeedMBps: Double
    public let writeSpeedMBps: Double
    public let testedAt: Date
    public let testFileSizeMB: Int
    
    public init(readSpeedMBps: Double, writeSpeedMBps: Double, testedAt: Date = Date(), testFileSizeMB: Int = 128) {
        self.readSpeedMBps = readSpeedMBps
        self.writeSpeedMBps = writeSpeedMBps
        self.testedAt = testedAt
        self.testFileSizeMB = testFileSizeMB
    }
    
    public var formattedRead: String {
        if readSpeedMBps >= 1000 {
            return String(format: "%.1f GB/s", readSpeedMBps / 1000.0)
        } else {
            return String(format: "%.0f MB/s", readSpeedMBps)
        }
    }
    
    public var formattedWrite: String {
        if writeSpeedMBps >= 1000 {
            return String(format: "%.1f GB/s", writeSpeedMBps / 1000.0)
        } else {
            return String(format: "%.0f MB/s", writeSpeedMBps)
        }
    }
}

public struct ExternalDrive: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var mountPath: String
    public var volumeUUID: String?
    public var totalCapacityBytes: Int64
    public var freeCapacityBytes: Int64
    public var usedCapacityBytes: Int64
    public var fileSystemType: String
    public var isReadOnly: Bool
    public var isRemovable: Bool
    public var isInternal: Bool
    public var isConnected: Bool
    public var connectionType: String
    public var detectedGamesCount: Int
    public var securityBookmarkData: Data?
    public var lastScanned: Date?
    public var benchmark: DriveBenchmarkResult?
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        mountPath: String,
        volumeUUID: String? = nil,
        totalCapacityBytes: Int64 = 0,
        freeCapacityBytes: Int64 = 0,
        usedCapacityBytes: Int64 = 0,
        fileSystemType: String = "APFS",
        isReadOnly: Bool = false,
        isRemovable: Bool = true,
        isInternal: Bool = false,
        isConnected: Bool = true,
        connectionType: String = "USB",
        detectedGamesCount: Int = 0,
        securityBookmarkData: Data? = nil,
        lastScanned: Date? = nil,
        benchmark: DriveBenchmarkResult? = nil
    ) {
        self.id = id
        self.name = name
        self.mountPath = mountPath
        self.volumeUUID = volumeUUID
        self.totalCapacityBytes = totalCapacityBytes
        self.freeCapacityBytes = freeCapacityBytes
        self.usedCapacityBytes = usedCapacityBytes > 0 ? usedCapacityBytes : max(0, totalCapacityBytes - freeCapacityBytes)
        self.fileSystemType = fileSystemType
        self.isReadOnly = isReadOnly
        self.isRemovable = isRemovable
        self.isInternal = isInternal
        self.isConnected = isConnected
        self.connectionType = connectionType
        self.detectedGamesCount = detectedGamesCount
        self.securityBookmarkData = securityBookmarkData
        self.lastScanned = lastScanned
        self.benchmark = benchmark
    }
    
    public var formattedTotalCapacity: String {
        return ByteCountFormatter.string(fromByteCount: totalCapacityBytes, countStyle: .file)
    }
    
    public var formattedFreeCapacity: String {
        return ByteCountFormatter.string(fromByteCount: freeCapacityBytes, countStyle: .file)
    }
    
    public var formattedUsedCapacity: String {
        return ByteCountFormatter.string(fromByteCount: usedCapacityBytes, countStyle: .file)
    }
    
    public var usedPercentage: Double {
        guard totalCapacityBytes > 0 else { return 0 }
        return Double(usedCapacityBytes) / Double(totalCapacityBytes)
    }
}
